# 对 single-end 支持实现代码的评估

## 总体评价

实现质量**高**。对照更新后的计划（`single_end_support_implementation_plan.md`）逐项检查，所有要求均已满足。核心的单端判定逻辑**正确无误**。上一轮评估中提出的 4 个关键问题全部得到了正确处理。

---

## 🔬 单端判定逻辑（你最关心的部分）

### SAM flag 过滤规则 — 完全正确

`auto_counting_withChrom.pl` 在 `$mode eq 'single'` 时的过滤管线：

| 步骤 | flag | single 模式行为 | 是否正确 |
|------|------|----------------|---------|
| paired bit | `0x1` | **不检查** (只在 pair 模式下检查) | ✅ |
| R1 filter | `0x40` | **不检查** (只在 pair 模式下检查) | ✅ |
| proper pair | `0x2` | **不检查** (只在 pair 模式下检查) | ✅ |
| mate unmapped | `0x8` | **不检查** (只在 pair 模式下检查) | ✅ |
| read unmapped | `0x4` | **排除** (所有模式共用) | ✅ |
| secondary | `0x100` | **排除** (所有模式共用) | ✅ |
| supplementary | `0x800` | **排除** (所有模式共用) | ✅ |
| MAPQ 阈值 | `$mapq` | **检查** (所有模式共用) | ✅ |
| 方向判断 | `0x10` | **使用 read 自身的 flag** (所有模式共用) | ✅ |

代码实现（`auto_counting_withChrom.pl` 第 186-215 行）：

```perl
# paired-end specific guards — 单端时整个 if 块被跳过
if ($mode eq 'pair') {
    next unless ($flag & 0x1);
    next unless ($flag & 0x40);
}

# unmapped check — 单端时只检查 0x4，mate unmapped 在 pair 模式下才检查
if (($flag & 0x4) || ($mode eq 'pair' && ($flag & 0x8))) { ... next; }

# secondary 和 supplementary 对所有模式生效
if ($flag & 0x100) { ... next; }
if ($flag & 0x800) { ... next; }

# MAPQ 检查 — 所有模式生效
if ($mapq < $mapq_threshold) { ... next; }

# proper pair — 只在 pair 模式下检查
if ($mode eq 'pair' && !($flag & 0x2)) { ... next; }

# 方向判断 — 所有模式生效，使用 0x10
if ($flag & 0x10) { $chrom_rev{$chrom}++; }
else              { $chrom_fwd{$chrom}++; }
```

**关键设计**：单端时不检查 mate unmapped (`0x8`) 是正确的——单端测序不存在 mate 概念。排除了 `0x4` 但不必排除 `0x8`。Perl 代码第 190 行用条件表达式 `($mode eq 'pair' && ($flag & 0x8))` 来实现这一点，简洁且正确。

### 核心算法完全保留

MAPQ ladder（`20 → 10 → 3 → 1`）、渐进投票（`3of3 → 4of5 → 6of7 → 7of8`）、二项检验（p < 0.01）、fallback 逻辑在 `auto_counting_withChrom.pl` 和旧的 `default_counting_withChrom.pl` 之间**逐行一致**。paired-end 模式下的行为与旧实现完全相同。

### SAM mode validation — 严格且正确

由于计划改为显式 `-m 1|2` 而非 auto-detect，`validate_sam_mode()` 函数会扫描 SAM 文件中**每一条** alignment record：

- `-m 1`（single）模式下遇到 `0x1` paired record → 立即 die，提示用 `-m 2`
- `-m 2`（pair）模式下遇到无 `0x1` 的 record → 立即 die，提示用 `-m 1`
- 没有任何 alignment record → die，提示 SAM 文件无数据

这解决了之前评估中提出的"auto 检测矛盾"问题——不再有 auto 模式，用户必须显式指定。

---

## ✅ 上一轮评估 4 个关键问题的解决状态

| # | 问题 | 状态 |
|---|------|------|
| 1 | `set -e` 导致 batch 错误处理失效 | **已修复**。batch 中使用 `if process_*; then ((success++)); else ((failed++)); fi` 结构，配合 `|| true` 处理算术溢出 |
| 2 | `resolveS.sam` 硬编码 batch 竞态 | **已修复**。`make_sam_path()` 函数为 batch 模式生成 `resolveS.sample_0001.sam` 等唯一文件名 |
| 3 | auto 检测后报错逻辑矛盾 | **已消除**。不再使用 auto-detect，改为显式 `-m 1|2`，SAM mode validation 报错清晰 |
| 4 | `MODE="single"` 命名冲突 | **已修复**。`MODE` 被替换为 `INPUT_KIND`（`fastq_single`/`fastq_pair`/`sam`/`batch`），语义清晰 |

---

## 📋 逐项验收

### `bin/resolveS` 主脚本

| 检查项 | 状态 | 详情 |
|--------|------|------|
| 版本号 | ✅ | `0.2.0` |
| `getopts` 增加 `m:` | ✅ | 校验只接受 `1` 或 `2` |
| `INPUT_KIND` 逻辑 | ✅ | `fastq_single`/`fastq_pair`/`sam`/`batch` 四种 |
| `-a`/`-1`/`-2`/`-b` 互斥 | ✅ | 三重检查，错误信息清晰 |
| `-m` 规则 | ✅ | SAM 必须有 `-m`，FASTQ 不能有 `-m`，batch SAM 必须有 `-m` |
| `-p`/`-u` SAM warning | ✅ | 只在 SAM 输入且用户显式设置时 warning |
| `detect_batch_kind` | ✅ | 第一行定类型，后续行必须一致，混合报错 |
| `check_dependencies(kind)` | ✅ | `fastq_single` 检查 single 对齐脚本，`fastq_pair` 检查 pair 对齐脚本，`sam` 无额外检查 |
| `make_sam_path` | ✅ | batch 模式生成 `resolveS.sample_NNNN.sam`，非 batch 用 `resolveS.sam` |
| `process_fastq_single` | ✅ | 对齐 → counting(single) → cleanup |
| `process_fastq_pair` | ✅ | 对齐 → counting(pair) → cleanup |
| `process_prealigned_sam` | ✅ | 直接 counting，接收 `sam_mode` 参数 |
| batch 错误处理 | ✅ | 用 `if/else` 而非 `local result=$?` |

### 对齐脚本

| 检查项 | 状态 | 详情 |
|--------|------|------|
| `default_align_by_bowtie2.sh` 增加 output_sam 参数 | ✅ | 第 6 个参数，默认 `resolveS.sam` |
| `default_align_by_bowtie2.sh` 增加 `--no-unal` | ✅ | |
| `default_align_single_by_bowtie2.sh` 存在 | ✅ | |
| 使用 `-U` 而非 `-1`/`-2` | ✅ | |
| 不包含 `--no-mixed`/`--no-discordant` | ✅ | |
| 包含 `--no-sq --no-unal` | ✅ | |
| 接受 output_sam 参数 | ✅ | 第 5 个参数，默认 `resolveS.sam` |

### 文件增删

| 检查项 | 状态 | 详情 |
|--------|------|------|
| `bin/auto_counting_withChrom.pl` 存在 | ✅ | 从旧 Perl 复制+扩展 |
| `bin/default_counting_withChrom.pl` 未被修改 | ✅ | |
| `bin/default_count_sam_primary.sh` 已删除 | ✅ | |
| `default_count_sam_primary` 无引用 | ✅ | 搜索代码库无结果 |

### 测试

| 检查项 | 状态 | 详情 |
|--------|------|------|
| `test_binomial_strand_detection.sh` 更新 `-m 2` | ✅ | |
| `test_sam_explicit_modes.sh` 新增 | ✅ | 覆盖 6 种场景 |
| `test_fastq_end_to_end.sh` 新增 | ✅ | 4 种场景（含 SAM re-analysis） |
| batch metadata 文件 | ✅ | 4 个文件各覆盖一种 batch kind |
| `test_prealigned_sam.sh` 更新 | ✅ | 添加 `-m 2` |
| `test_batch_sam.sh` 更新 | ✅ | 添加 `-m 1` 和 `-m 2` |
| `test_batch_fastq.sh` 更新 | ✅ | 不加 `-m`（FASTQ 模式不需要） |

### 文档

| 检查项 | 状态 | 详情 |
|--------|------|------|
| `print_usage()` 更新 | ✅ | 含 4 种示例 + `-m` 说明 |
| README.md 更新 | ✅ | |
| README_zh.md 更新 | ✅ | |

---

## 🟡 次要发现

### 1. 死代码（继承自旧 Perl）

`auto_counting_withChrom.pl` 和 `default_counting_withChrom.pl` 中：
- `%chrom_status` hash 被赋值（`unmapped`/`sec`/`supp`/`not_proper`）但从未被读取或输出。
- `$insuff_count` 被 `count_strand_types` 返回但调用方从未使用。

这些是旧代码的遗留，不影响功能。



作者审批：帮我修改吧

### 2. 错误信息级别不一致

`auto_counting_withChrom.pl` 参数解析报错说 `must be 'single' or 'pair'`（Perl 层面），但 `validate_sam_mode` 报错说 `use -m 2` / `use -m 1`（shell wrapper 层面）。如果用户直接调用 Perl 脚本会困惑。但考虑到 Perl 脚本总是由 `resolveS` shell wrapper 调用，不影响实际使用。



作者审批：帮我修改吧

### 3. `test_binomial_strand_detection.sh` 只测了 paired-end

该测试只用 `-m 2`（paired-end SAM），没有覆盖 `-m 1`（single-end SAM）的二项检验场景。建议增加一组 single-end synthetic SAM 测试。



作者审批：先算了

### 4. 测试数据路径不可移植

`test_fastq_end_to_end.sh` 和 `test_batch_fastq.sh` 引用 `/mnt/yusim/dalang/projects/...` 下的真实 FASTQ 文件，在其他机器上无法运行。计划中已注明此限制，不算遗漏。

作者审批：先算了，不要管了

### 5. `test_prealigned_sam.sh` 只测了 paired-end

类似测试覆盖 gap——只有 `-m 2` 没有 `-m 1`。



作者审批：是吗？写一下

---

## 结论

**实现质量很高，单端判定逻辑正确，可以提交。** 计划中所有关键功能均已正确实现，4 个上一轮评估发现的问题全部得到解决。发现的次要问题（死代码、测试覆盖 gap、路径可移植性）不影响功能正确性，可以在后续迭代中处理。
