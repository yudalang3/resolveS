# 对 single_end_support_implementation_plan.md 的评估

## 总体评价

这是一个**结构良好、考虑周全**的落地计划。核心架构决策（新增文件而非修改现有代码、SAM flag 自动检测、保持输出列不变）是正确的。边界约束清晰，实现顺序合理。

但存在一些需要修正的问题，按严重程度排列如下：

---

## 🔴 需要修正的问题

### 1. `set -e` 导致 batch 模式错误处理全部失效（严重，已存在 bug）

`bin/resolveS` 第 12 行设置了 `set -e`。当任一子调用返回非零时，bash 立即退出——控制流永远不会到达 `local result=$?`、`((failed++))` 或错误日志。当前 `process_batch` 和 `process_batch_sam` 中的错误计数和"跳过失败样本继续处理"逻辑全是死代码。

计划中提出的统一 `process_batch` 继承了相同的结构，但完全没有提及 `set -e` 问题。

**建议**：要么去掉 `set -e` 并改为显式错误处理，要么在每个子调用处使用 `|| { ((failed++)) || true; log_error "..."; }` 内联写法。

### 2. `resolveS.sam` 硬编码文件名在 batch 模式下的竞态（已存在 bug）

两个 alignment 脚本都硬编码输出为 CWD 下的 `resolveS.sam`。batch 模式下每个样本都会覆盖前一个样本的文件。结尾 cleanup 只删除最后一个样本的文件。`-d` 在 batch 模式下基本无意义。

**建议**：方案中应明确说明此问题。短期 fix：每个样本使用 `mktemp` 生成唯一文件名；长期 fix：每个样本在独立子目录中运行。

### 3. auto 模式检测后报错逻辑矛盾（新增 bug）

Section 3.3 规定 `single` 模式下遇到 `0x1` 就 die 报错，但 `auto` 模式只扫描前 1000 条记录选 dominant type。如果 95% 是 unpaired、5% 有 `0x1`，auto 选 `single`，然后 counting 阶段在遇到少数 `0x1` 记录时 fatal error——用户看到一个 auto 判定为 single 的文件却报错，体验很差。

**建议**：`auto` 模式选 dominant type 后，counting 阶段对 minority type 的记录应**静默跳过**（最多 stderr warning），不应 fatal。如果两种类型都大量存在（如各占 30%+），`auto` 才应拒绝并报错。



作者：我建议这个自动模式去掉。因为直接输入 fastq 文件可以明确的判定它是单端还是双端。另外，如果输入的是杠 a 命令，直接输入 sam 文件，那就新增一个 -m 可以输入1或者2，表示单端或者双端，同时写好这个使用说明。这样就简化处理了

### 4. `MODE="single"` 命名冲突

当前代码中 `MODE="single"` 表示"单样本 paired-end"模式（即 `-1` + `-2`）。计划新增 `INPUT_KIND` 来区分 `fastq_pair` / `fastq_single` / `sam` / `batch`，但 `MODE` 变量名仍然存在，可能在实现中造成混淆。

**建议**：将现有 `MODE` 重命名为 `INPUT_MODE` 或完全用 `INPUT_KIND` 替代，避免变量名暗示"single=单端"而实际是"single=单样本paired"。

---

## 🟡 建议改进的问题

### 5. 代码重复风险

计划新建 `auto_counting_withChrom.pl`（~500 行）作为 `default_counting_withChrom.pl`（423 行）的拷贝+扩展。核心逻辑（渐进投票 3of3→4of5→6of7→7of8、自适应 MAPQ 20→10→3→1、二项检验、fallback）完全重复约 350 行。任何算法 bug 需要两边修。

计划将此标记为有意为之（"不修改原文件"），但应明确说明：`default_counting_withChrom.pl` 是否最终变成 dead code、是否后续会删除、还是作为向后兼容保留。

**建议**：在计划中加上过渡策略说明——如"第一阶段保留两文件、第二阶段统一迁移到 `auto_counting_withChrom.pl` 后删除旧文件"。

作者：这个先忽略，不用管

### 6. 测试数据路径不可移植

Section 4.3 中的 FASTQ 测试数据路径（`/mnt/yusim/dalang/projects/...`）是特定机器的路径，其他人无法运行。

**建议**：测试脚本应检查数据是否存在，不存在则 skip（非 fail）；或生成 minimal synthetic FASTQ（类似 `test_binomial_strand_detection.sh` 生成 synthetic SAM）。



作者：这个先忽略，不用管

### 7. 单端 bowtie2 缺少 `--no-unal`

Section 3.2 的单端 bowtie2 命令用了 `--no-sq` 但没用 `--no-unal`。不用 `--no-unal` 意味着未比对 reads（flag 0x4）也会写入 SAM，增加 I/O 开销。Perl 统计脚本尽管会过滤掉这些记录，但 SAM 文件更大。

**建议**：加上 `--no-unal`，或文档说明为何不加。



作者：这个挺好的，添加上去吧。--no-unal 在单端和双端测序中都添加上去吧。

### 8. `-d` 标志语义过载

`-d` 同时控制两件事：(a) 保留 `resolveS.sam`；(b) Perl verbose stderr 输出。集成测试用 `-d` 保留 SAM，但同时会产生大量 per-rRNA 调试表格输出到 stderr。

**建议**：计划中至少注明此限制，未来可考虑拆分（如 `--keep-sam` vs `--debug-perl`）。



作者：这个先忽略，不用管

---

## 🟢 其他小问题

### 9. batch 元数据逐行检测实现细节

Section 2 规定 1 列 metadata 按扩展名区分 FASTQ/SAM，但当前代码只读第一行决定整批模式。计划中 `process_batch` 的描述说"读取每一条"是正确的，但实现时容易沿袭只读第一行的模式。建议加入显式伪代码。

### 10. `-p` 和 `-u` 在 `-a` 模式下静默忽略

用 `-a`（预比对 SAM）时 `-p` 和 `-u` 无意义，当前代码静默接受。建议至少 stderr 警告。



作者：对，应该添加警告

### 11. `process_prealigned_sam()` 修改未详述

计划提到 SAM 模式改为调用 `auto_counting_withChrom.pl ... auto`，但没有明确描述 `process_prealigned_sam()` 函数体的具体改动。实现时应确认该函数也被更新。



作者：对这个看看

---

## ✅ 计划做得好的地方

1. **新增而非修改**：`auto_counting_withChrom.pl` + `default_align_single_by_bowtie2.sh`，不碰 `default_counting_withChrom.pl`，保持向后兼容
2. **SAM flag 过滤正确**：单端模式正确排除了 0x4/0x100/0x800/MAPQ，不检查 0x1/0x2/0x40/0x8
3. **`-u` 参数语义更新**：文档和日志按 read/pair 区分
4. **批量 metadata 扩展名检测**：大小写不敏感，错误明确
5. **测试分层完善**：静态检查 → 现有测试 → 新集成测试 → SAM auto-detect 测试 → batch 测试
6. **测试目录隔离**：每个 case 独立子目录运行，避免竞态
7. **README 中英文同步**：符合项目规则
8. **清理 `default_count_sam_primary.sh`**：确认为 dead code，无引用
9. **实现顺序合理**：先新增 Perl（最复杂），再新增 shell（简单），改主脚本，最后测试文档

---

## 建议的实现时额外关注点

| 关注点 | 说明 |
|--------|------|
| batch 模式第一行推断类型后校验后续 | 混合 1 列/2 列的 metadata 文件应报错 |
| case-insensitive 扩展名匹配 | bash 4+ 用 `${var,,}`，或 `shopt -s nocasematch` |
| MAPQ 阈值最低为 1（非 0） | 与现有行为一致，排除 MAPQ=0 纯多比对 |
| `check_dependencies()` 调用时机 | 必须在 `INPUT_KIND` 确定后调用；batch 需先读 metadata 第一行 |
| `-a` 与 `-1/-2` 互斥检测 | 应在 `getopts` 后显式检查并报错 |

---

## 结论

计划整体质量**高**，可以在此基础上实现。需要修正的 4 个关键问题中，\#1 和 \#2 是已存在的 bug（非计划引入），\#3 是计划新增逻辑的矛盾，\#4 是命名混淆。建议在实现前修正计划中的这些问题，特别是 \#3（auto 模式报错逻辑）和 \#4（命名），其他可以在实现过程中处理。
