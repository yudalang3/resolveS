# 空 SAM 的友好错误处理实施方案

## 1. 目标与边界

当 FASTQ 比对未产生 alignment records，或用户提供的 SAM 不含 alignment records 时，在 Bash 主程序中提前给出面向用户的错误信息，不再让用户直接看到 Perl 的原始 `die`。Perl 仍保留相同检查，作为直接调用计数脚本或 Bash 检查失效时的防御性保护。

本次修改只处理“没有 alignment records”这一边界，不扩展为完整的 SAM 格式校验，也不把“只有 unmapped records”重新定义为空 SAM。正常流程和其他失败流程的既有清理行为不在本次修改范围内。

## 2. 当前行为与判定边界

相关代码：

- [`bin/resolveS`](../../bin/resolveS)：FASTQ 比对、pre-aligned SAM 计数、临时 SAM 清理和 batch 调度。
- [`bin/auto_counting_withChrom.pl`](../../bin/auto_counting_withChrom.pl)：读取 SAM；当 `$alignment_records == 0` 时执行 `die "No alignment records found in SAM file\n"`。
- [`bin/default_align_by_bowtie2.sh`](../../bin/default_align_by_bowtie2.sh) 和 [`bin/default_align_single_by_bowtie2.sh`](../../bin/default_align_single_by_bowtie2.sh)：使用 `--no-unal`；没有匹配记录时，bowtie2 仍可能成功退出并留下 0 字节或仅含 header 的 SAM。

Perl 当前对 `$alignment_records` 的判定规则是：

1. 跳过首字符为 `@` 的 header 行。
2. 对其他行按制表符分列；字段少于 2 个时跳过。
3. 字段至少为 2 个时计为一条 alignment record，之后才进行 mode、flag 和 MAPQ 过滤。

因此 Bash 层必须使用相同边界。空文件、仅 header、header 后只有空行或无制表符的空白行均应失败；包含至少一条具有两个或更多制表符分隔字段的非 header 行则应通过。这里不要求该记录已比对，也不做 11 个 SAM 必需字段的完整验证。

## 3. 实现方案

### 3.1 在 `bin/resolveS` 增加统一检查函数

在 `cleanup_sam()` 附近新增 `check_sam_has_alignments()`：

```bash
check_sam_has_alignments() {
    local sam_path="$1"

    [[ -s "$sam_path" ]] || return 1

    awk -F '\t' '
        substr($0, 1, 1) != "@" && NF >= 2 {
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$sam_path"
}
```

使用 `awk` 而不是 `grep -v '^@'`，避免把空行或普通空白行误判为 alignment record。`substr($0, 1, 1) != "@"` 和 `NF >= 2` 分别对应 Perl 的 header 跳过及最小字段数判断。

### 3.2 FASTQ 单端和双端路径

在 `process_fastq_single()` 和 `process_fastq_pair()` 中，bowtie2 成功返回后、计算输入绝对路径和调用 Perl 之前执行检查。两条路径使用一致的核心提示：

```bash
if ! check_sam_has_alignments "$sam_path"; then
    log_error "No alignment records were produced from the FASTQ input."
    log_error "Possible causes include low rRNA content, an rRNA reference that does not match the sample, or a -u sampling range that is too small."
    log_error "The generated SAM file has been kept for diagnosis: $sam_path"
    return 1
fi
```

提示只陈述“没有产生 alignment records”，不把某个可能原因表述为确定结论。`-u` 只出现在 FASTQ 场景中；用户可据此检查抽样范围，同时检查 `-r` 指向的 reference 是否适合样本。

这个失败分支不得调用 `cleanup_sam()`。无论是否启用 `-d`，生成的空 SAM 都保留作诊断文件。成功路径以及 alignment/counting 的其他既有失败路径保持原样。

### 3.3 Pre-aligned SAM 路径

在 `process_prealigned_sam()` 完成文件存在性和 `-m` 校验后、调用 Perl 之前执行相同检查：

```bash
if ! check_sam_has_alignments "$sam_file"; then
    log_error "The provided SAM file contains no alignment records: $sam_file"
    log_error "Check whether the file is empty, contains only headers, or was not generated correctly."
    return 1
fi
```

pre-aligned SAM 不经过 resolveS 的 FASTQ 抽样或比对，因此提示中不得建议调整 `-u`，也不需要清理用户提供的文件。

### 3.4 退出与 batch 行为

- 单样本 FASTQ 或 SAM：处理函数返回 1，主流程以非零状态退出。
- Batch：沿用 `process_batch()` 的现有控制流。空 SAM 样本计入 `failed` 并记录 `Failed to process sample ...`，循环继续处理后续样本；batch 汇总后只要 `failed > 0`，程序最终返回非零。
- 输出表头由现有 `emit_header()` 生成。失败样本不得追加结果行；单样本失败时 stdout 或 `-o` 文件应只有既有表头，batch 输出只包含成功样本的结果行。

### 3.5 明确不修改的组件

| 文件 | 处理 |
|---|---|
| [`bin/auto_counting_withChrom.pl`](../../bin/auto_counting_withChrom.pl) | 保留 `die "No alignment records found in SAM file\n"`，作为防御性检查。 |
| [`bin/default_align_by_bowtie2.sh`](../../bin/default_align_by_bowtie2.sh) | 不修改 alignment 命令或 bowtie2 参数。 |
| [`bin/default_align_single_by_bowtie2.sh`](../../bin/default_align_single_by_bowtie2.sh) | 不修改 alignment 命令或 bowtie2 参数。 |
| [`README.md`](../../README.md)、[`README_zh.md`](../../README_zh.md) | 本问题不改变公开用法，方案不要求修改 README。 |

## 4. 测试计划

### 4.1 自动化 SAM 测试

扩展 [`tests/test_sam_explicit_modes.sh`](../../tests/test_sam_explicit_modes.sh)，使用临时目录自动构造并验证以下输入：

| 场景 | 预期 |
|---|---|
| 0 字节 SAM | 失败 |
| 仅含 `@HD`/`@SQ` header | 失败 |
| header 后只有空行或无制表符的空白行 | 失败 |
| 至少一条满足当前 Perl 最小字段边界的非 header 行 | 通过 Bash 的空 SAM 检查 |
| 现有正常 single-end SAM | 成功并输出一条结果 |
| 现有正常 paired-end SAM | 成功并输出一条结果 |

每个空 SAM 用例至少断言：

1. 命令退出码非零。
2. stderr 包含 Bash 层友好提示和输入路径。
3. stderr 不包含 Perl 原始错误 `No alignment records found in SAM file`，证明 Perl 未被调用到该失败点。
4. stdout 或 `-o` 输出仅有现有表头，没有样本结果行。

在同一测试中增加 SAM batch：元数据依次包含空 SAM 和有效 SAM，断言空样本计为失败、有效样本仍被处理、汇总为 1 success/1 failed、输出只有有效样本结果，并且 batch 最终退出非零。

### 4.2 FASTQ 端到端验证

覆盖单端和双端 FASTQ 中至少一种无匹配数据，以及现有正常数据：

- 无匹配 reads：bowtie2 本身成功，resolveS 随后非零退出；stderr 包含 FASTQ 专用提示、三类可能原因及诊断 SAM 路径，不包含 Perl 原始错误。
- 诊断文件：无匹配失败时，无 `-d` 和有 `-d` 两种运行均保留生成的 SAM。
- 正常 FASTQ：仍产生结果；无 `-d` 时沿用正常清理，有 `-d` 时沿用现有保留行为。
- 输出：失败运行的 stdout 或 `-o` 文件只有表头，不得出现结果行。

新增自包含的 [`tests/test_empty_fastq_handling.sh`](../../tests/test_empty_fastq_handling.sh)，用仓库自带 bowtie2 和默认 index 验证无匹配及正常 FASTQ；[`examples/test_fastq_end_to_end.sh`](../../examples/test_fastq_end_to_end.sh) 继续作为现有真实数据验证。测试环境缺少示例所依赖的外部 FASTQ 时，应明确报告未运行，不能把该项伪装成通过。

### 4.3 全量回归

完成实现后运行现有 shell 回归：

```bash
bash tests/test_sam_explicit_modes.sh
bash tests/test_empty_fastq_handling.sh
bash tests/test_mapq_adaptive_regression.sh
bash tests/test_binomial_strand_detection.sh
bash examples/test_prealigned_sam.sh
bash examples/test_batch_sam.sh
bash examples/test_fastq_end_to_end.sh
bash examples/test_batch_fastq.sh
```

重点确认 SAM explicit mode、single/pair mode 校验、MAPQ 自适应和二项检验结果不受影响。依赖机器外部 FASTQ 的测试若无法运行，需在验证记录中单独列为未运行及说明原因。

## 5. 验收标准

1. Bash 与 Perl 对“是否存在 alignment records”的边界一致，空白行不会被误判。
2. FASTQ 和 pre-aligned SAM 分别显示适用的友好错误，且用户看不到 Perl 原始 `die`。
3. 空 FASTQ 生成的 SAM 在失败时保留，不受 `-d` 状态影响。
4. 单样本失败返回非零；batch 继续后续样本，并在存在失败时最终返回非零。
5. 空样本不产生结果行，正常 SAM/FASTQ 行为及现有回归测试保持不变。
6. alignment 脚本和 Perl 防御检查不修改。

## 6. 版本与文档检查

实现时确认这是一项用户可见但不改变 CLI 的错误处理修复，因此将 [`bin/resolveS`](../../bin/resolveS) 的用户可见版本和 [`docs/make_portable_program.sh`](../make_portable_program.sh) 的打包版本同步提升为补丁版本 `0.2.2`。

本次方案文档本身不修改 README。若后续实现同时改变公开用法或用户文档，则必须同步更新英文 [`README.md`](../../README.md) 和中文 [`README_zh.md`](../../README_zh.md)。
