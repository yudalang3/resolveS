# resolveS 单端测序支持实施方案

> 本文件是单端测序支持任务的最终执行文档。实现者只需要阅读并执行本文件，不需要了解前期设计讨论。

## 1. 目标

为 `resolveS` 增加 single-end RNA-seq 支持，同时保持现有 paired-end 工作流可用。

最终用户接口：

```bash
# single-end FASTQ: 只有 -1，自动进入单端模式
resolveS -1 sample.fastq.gz

# paired-end FASTQ: 同时有 -1 和 -2，进入双端模式
resolveS -1 sample_R1.fastq.gz -2 sample_R2.fastq.gz

# single-end SAM: -a 输入 SAM，-m 1 明确指定单端
resolveS -a aligned.sam -m 1

# paired-end SAM: -a 输入 SAM，-m 2 明确指定双端
resolveS -a aligned.sam -m 2
```

核心原则：

- FASTQ 输入根据参数自动判断 single-end 或 paired-end。
- SAM 输入不自动判断，必须通过 `-m 1|2` 显式指定。
- 不修改 `bin/default_counting_withChrom.pl`。
- 新增 `bin/auto_counting_withChrom.pl` 承载新的 `single|pair` mode-aware counting 逻辑。
- 删除遗留文件 `bin/default_count_sam_primary.sh`。
- paired-end 和 single-end bowtie2 alignment 都添加 `--no-unal`。
- README 更新必须中英文同步。

## 2. 用户接口规格

### 2.1 FASTQ 输入

| 命令 | 模式 |
| --- | --- |
| `resolveS -1 sample.fq.gz` | single-end FASTQ |
| `resolveS -1 R1.fq.gz -2 R2.fq.gz` | paired-end FASTQ |

FASTQ 模式不使用 `-m`。如果用户在 FASTQ 模式传入 `-m`，直接报错：

```text
[ERROR] -m is only valid for SAM input (-a or SAM batch)
```

### 2.2 SAM 输入

| 命令 | 模式 |
| --- | --- |
| `resolveS -a aligned.sam -m 1` | single-end SAM |
| `resolveS -a aligned.sam -m 2` | paired-end SAM |

规则：

- `-a` 模式必须传 `-m`。
- `-m` 只能是 `1` 或 `2`。
- `-m 1` 映射为 counting mode `single`。
- `-m 2` 映射为 counting mode `pair`。
- `-a` 模式下如果用户显式传入 `-p` 或 `-u`，继续运行但输出 warning，因为 SAM 输入不运行 bowtie2。

建议 warning 文案：

```text
[WARN] -p is ignored for SAM input because no alignment is run
[WARN] -u is ignored for SAM input because no alignment is run
```

### 2.3 batch 输入

`-b` metadata 必须是同质批次。不支持在同一个 metadata 文件中混合 single FASTQ、paired FASTQ 和 SAM。

第一条有效记录决定 batch kind，后续有效记录必须与它一致。

| metadata 格式 | batch kind | `-m` 规则 |
| --- | --- | --- |
| 1 列 `.fq/.fastq/.fq.gz/.fastq.gz` | single-end FASTQ batch | 禁止传 `-m` |
| 1 列 `.sam` | SAM batch | 必须传 `-m 1` 或 `-m 2` |
| 2 列 | paired-end FASTQ batch | 禁止传 `-m` |

示例：

```bash
# single-end FASTQ batch: metadata 每行 1 个 FASTQ
resolveS -b batch_single_fastq_metadata.txt

# paired-end FASTQ batch: metadata 每行 R1<TAB>R2
resolveS -b batch_pair_fastq_metadata.txt

# single-end SAM batch: metadata 每行 1 个 SAM
resolveS -b batch_sam_metadata.txt -m 1

# paired-end SAM batch: metadata 每行 1 个 SAM
resolveS -b batch_sam_metadata.txt -m 2
```

### 2.4 `-u` 参数语义

`-u` 继续表示百万级限制，但文案需要区分：

- single-end FASTQ：maximum reads to align, in millions。
- paired-end FASTQ：maximum read pairs to align, in millions。
- SAM 输入：忽略 `-u` 并 warning。

## 3. 文件级修改方案

### 3.1 `bin/resolveS`

#### 3.1.1 版本号和帮助信息

在 `print_usage()` 中更新版本号：

```text
This is resolveS version 0.2.0
```

帮助信息必须包括：

- single-end FASTQ 示例：`resolveS -1 sample.fastq.gz`
- paired-end FASTQ 示例：`resolveS -1 R1.fastq.gz -2 R2.fastq.gz`
- single-end SAM 示例：`resolveS -a aligned.sam -m 1`
- paired-end SAM 示例：`resolveS -a aligned.sam -m 2`
- `-m <1|2>` 只用于 SAM 输入。
- `-p/-u` 对 SAM 输入无效。

#### 3.1.2 参数变量

用明确变量替代旧的 `MODE="single"` 语义，避免把“单样本”和“单端”混淆：

```bash
INPUT_KIND=""             # fastq_single | fastq_pair | sam | batch
BATCH_KIND=""             # fastq_single | fastq_pair | sam
SAM_MODE=""               # single | pair
M_OPTION=""               # raw -m value: 1 | 2
THREADS_SET=false
MAX_ALIG_READS_SET=false
CURRENT_BATCH_INDEX=0
```

`getopts` 增加 `m:`：

```bash
while getopts "1:2:a:b:o:p:u:r:m:dh" opt; do
```

`-m` 校验：

```bash
case "$OPTARG" in
    1)
        M_OPTION="1"
        SAM_MODE="single"
        ;;
    2)
        M_OPTION="2"
        SAM_MODE="pair"
        ;;
    *)
        log_error "Invalid -m value: $OPTARG (must be 1 for single-end SAM or 2 for paired-end SAM)"
        exit 1
        ;;
esac
```

在解析 `-p` 和 `-u` 时记录用户是否显式传入：

```bash
THREADS_SET=true
MAX_ALIG_READS_SET=true
```

#### 3.1.3 参数互斥检查

解析完参数后必须检查：

- `-a` 不能和 `-1/-2/-b` 同时使用。
- `-b` 不能和 `-1/-2/-a` 同时使用。
- `-2` 不能在没有 `-1` 的情况下使用。

输入模式判断：

```bash
if [[ -n "$SAM_FILE" ]]; then
    INPUT_KIND="sam"
elif [[ -n "$METADATA_FILE" ]]; then
    INPUT_KIND="batch"
elif [[ -n "$R1_FILE" && -n "$R2_FILE" ]]; then
    INPUT_KIND="fastq_pair"
elif [[ -n "$R1_FILE" ]]; then
    INPUT_KIND="fastq_single"
else
    log_error "Please specify FASTQ (-1, optionally -2), SAM (-a with -m), or batch (-b)"
    print_usage
    exit 1
fi
```

`-m` 规则：

- `INPUT_KIND="sam"`：必须有 `SAM_MODE`。
- `INPUT_KIND="fastq_single"` 或 `fastq_pair`：如果有 `SAM_MODE`，报错。
- `INPUT_KIND="batch"`：先检测 `BATCH_KIND`，再决定 `-m` 是否必需或非法。

SAM 输入 warning：

```bash
if [[ "$INPUT_KIND" == "sam" ]]; then
    [[ "$THREADS_SET" == true ]] && log_warn "-p is ignored for SAM input because no alignment is run"
    [[ "$MAX_ALIG_READS_SET" == true ]] && log_warn "-u is ignored for SAM input because no alignment is run"
fi
```

batch SAM 也同样 warning。

#### 3.1.4 batch kind 检测

新增函数：

```bash
detect_batch_kind <metadata>
```

职责：

- 跳过空行和 `#` 注释行。
- 第一条有效记录决定 expected kind。
- 后续有效记录必须匹配 expected kind。
- 不执行样本处理，只做 metadata 校验和类型判断。
- metadata 为空时报错。

判断规则：

```bash
expected=""
while IFS= read -r line || [[ -n "$line" ]]; do
    # skip empty/comment
    # column_count by tab

    if [[ "$column_count" -eq 2 ]]; then
        current="fastq_pair"
    elif [[ "$column_count" -eq 1 ]]; then
        path="$line"
        lower="${path,,}"
        if [[ "$lower" =~ \.sam$ ]]; then
            current="sam"
        elif [[ "$lower" =~ \.(fq|fastq)(\.gz)?$ ]]; then
            current="fastq_single"
        else
            log_error "Cannot detect metadata type from one-column path: $path"
            return 1
        fi
    else
        log_error "Invalid metadata format: expected 1 or 2 tab-separated columns"
        return 1
    fi

    if [[ -z "$expected" ]]; then
        expected="$current"
    elif [[ "$current" != "$expected" ]]; then
        log_error "Mixed metadata types are unsupported"
        return 1
    fi
done < "$metadata"
```

#### 3.1.5 依赖检查

`check_dependencies()` 改为接收 kind：

```bash
check_dependencies <kind>
```

规则：

- 所有 kind 都需要 `bin/auto_counting_withChrom.pl`。
- `fastq_pair` 需要：
  - bowtie2 index：`${REFERENCE_DB}.1.bt2`
  - `bin/default_align_by_bowtie2.sh`
- `fastq_single` 需要：
  - bowtie2 index：`${REFERENCE_DB}.1.bt2`
  - `bin/default_align_single_by_bowtie2.sh`
- `sam` 不检查 bowtie2 index 和 alignment 脚本。

batch 模式必须先检测 `BATCH_KIND`，再调用：

```bash
check_dependencies "$BATCH_KIND"
```

#### 3.1.6 每个样本的 SAM 输出路径

现有流程硬编码 `resolveS.sam`，batch 中会覆盖。需要改成主流程生成 SAM 路径并传给 alignment 脚本。

建议函数：

```bash
make_sam_path <sample_index>
```

规则：

- 非 batch 单样本默认仍使用当前目录 `resolveS.sam`，保持用户习惯。
- batch 模式使用唯一文件名，例如：

```text
resolveS.sample_0001.sam
resolveS.sample_0002.sam
```

或：

```text
resolveS.<pid>.<sample_index>.sam
```

清理规则：

- `DEBUG=false` 时，每个样本 counting 完成后删除该样本 SAM。
- `DEBUG=true` 时保留所有样本 SAM，并在 stderr log 中打印保留路径。

不要只在脚本最后删除一个全局 `resolveS.sam`。

#### 3.1.7 处理函数

建议函数签名：

```bash
process_fastq_single <read> <output> <threads> <max_alig_reads> <sam_path>
process_fastq_pair <r1> <r2> <output> <threads> <max_alig_reads> <sam_path>
process_prealigned_sam <sam_file> <output> <sam_mode>
```

`process_fastq_single()` 调用：

```bash
"${SCRIPT_DIR}/default_align_single_by_bowtie2.sh" "$read" "$REFERENCE_DB" "$threads" "$max_alig_reads" "$sam_path"
perl "${SCRIPT_DIR}/auto_counting_withChrom.pl" "$sam_path" "$output_target" "$fullpath" "$debug_flag" single
```

`process_fastq_pair()` 调用：

```bash
"${SCRIPT_DIR}/default_align_by_bowtie2.sh" "$r1" "$r2" "$REFERENCE_DB" "$threads" "$max_alig_reads" "$sam_path"
perl "${SCRIPT_DIR}/auto_counting_withChrom.pl" "$sam_path" "$output_target" "$fullpath" "$debug_flag" pair
```

`process_prealigned_sam()` 必须改成显式接收 `sam_mode`：

```bash
process_prealigned_sam() {
    local sam_file="$1"
    local output="$2"
    local sam_mode="$3"   # single | pair

    if [[ ! -f "$sam_file" ]]; then
        log_error "SAM file not found: $sam_file"
        return 1
    fi

    if [[ "$sam_mode" != "single" && "$sam_mode" != "pair" ]]; then
        log_error "SAM mode is required for SAM input (-m 1 or -m 2)"
        return 1
    fi

    local fullpath
    fullpath=$(realpath "$sam_file")

    local debug_flag=0
    [[ "$DEBUG" == true ]] && debug_flag=1

    local output_target="${output:--}"

    if ! perl "${SCRIPT_DIR}/auto_counting_withChrom.pl" "$fullpath" "$output_target" "$fullpath" "$debug_flag" "$sam_mode"; then
        log_error "SAM counting failed: $fullpath"
        return 1
    fi
}
```

#### 3.1.8 batch 错误处理

当前 `set -e` 会让子调用失败时提前退出，导致 `failed++` 等逻辑失效。batch 中必须使用 `if process_*; then ... else ... fi`。

不要写：

```bash
process_fastq_pair ...
local result=$?
```

应写：

```bash
if process_fastq_pair "$r1" "$r2" "$output_file" "$threads" "$max_alig_reads" "$sam_path"; then
    ((success++)) || true
else
    ((failed++)) || true
    log_error "Failed to process sample $current: $r1"
fi
```

所有 batch 分支都使用同样结构。

### 3.2 `bin/default_align_by_bowtie2.sh`

paired-end alignment 脚本做两个改动。

新增可选输出 SAM 参数：

```bash
default_align_by_bowtie2.sh <read1.fq> <read2.fq> <genome_index> [threads] [max_alig_reads] [output_sam]
```

默认：

```bash
OUTPUT_SAM="${6:-resolveS.sam}"
```

bowtie2 命令添加 `--no-unal`，并写入指定输出文件：

```bash
"$BOWTIE2_BIN" -p "$THREADS" \
  -u "$MAX_ALIG_READS" --no-sq --no-unal \
  --no-mixed --no-discordant \
  -x "$G_INDEX" \
  -1 "$READ1" \
  -2 "$READ2" \
  -S "$OUTPUT_SAM"
```

### 3.3 新增 `bin/default_align_single_by_bowtie2.sh`

脚本用途：single-end FASTQ 到 SAM。

接口：

```bash
default_align_single_by_bowtie2.sh <read.fq> <genome_index> [threads] [max_alig_reads] [output_sam]
```

默认：

```bash
OUTPUT_SAM="${5:-resolveS.sam}"
```

核心命令：

```bash
"$BOWTIE2_BIN" -p "$THREADS" \
  -u "$MAX_ALIG_READS" --no-sq --no-unal \
  -x "$G_INDEX" \
  -U "$READ" \
  -S "$OUTPUT_SAM"
```

single-end 脚本不要使用 paired-end 专用参数：

- 不使用 `--no-mixed`
- 不使用 `--no-discordant`
- 不使用 `-1`
- 不使用 `-2`

### 3.4 新增 `bin/auto_counting_withChrom.pl`

从 `bin/default_counting_withChrom.pl` 复制当前实现到新文件，再扩展为显式 mode-aware counting。原文件不修改。

#### 3.4.1 命令行接口

```bash
auto_counting_withChrom.pl <input_sam_file> [output_file] [index_str] [debug=0] <mode>
```

`mode` 必须是：

- `single`
- `pair`

不提供 mode 或 mode 非法时直接报错。

不支持 `auto` mode。

#### 3.4.2 SAM mode validation

正式统计前先验证 SAM records 与显式 mode 是否一致。

建议函数：

```perl
sub validate_sam_mode {
    my ($input_file, $mode) = @_;
    ...
}
```

规则：

- `single` mode：
  - alignment record 不应设置 paired bit `0x1`。
  - 如果发现 paired record，报错：

```text
SAM contains paired-end records but -m 1 was used; use -m 2 for paired-end SAM
```

- `pair` mode：
  - alignment record 应设置 paired bit `0x1`。
  - 如果发现 unpaired record，报错：

```text
SAM contains single-end records but -m 2 was used; use -m 1 for single-end SAM
```

- 如果没有任何 alignment record，报错：

```text
No alignment records found in SAM file
```

#### 3.4.3 paired-end counting 规则

保持旧 Perl 的 paired-end 语义：

- 必须设置 `0x1` paired。
- 必须设置 `0x40` R1。
- 排除 `0x4` read unmapped。
- 排除 `0x8` mate unmapped。
- 排除 `0x100` secondary。
- 排除 `0x800` supplementary。
- 必须满足 MAPQ 阈值。
- 必须设置 `0x2` proper pair。
- 用 R1 的 `0x10` 判断方向：
  - 未设置：forward。
  - 设置：reverse。

#### 3.4.4 single-end counting 规则

single-end SAM 没有 R1/R2/proper-pair/mate 概念：

- 不要求 `0x1`。
- 不检查 `0x2` proper pair。
- 不检查 `0x8` mate unmapped。
- 不检查 `0x40` R1。
- 排除 `0x4` read unmapped。
- 排除 `0x100` secondary。
- 排除 `0x800` supplementary。
- 必须满足 MAPQ 阈值。
- 用 read 自身 `0x10` 判断方向：
  - 未设置：forward。
  - 设置：reverse。

其余检测算法保持旧实现：

- MAPQ ladder：20 -> 10 -> 3 -> 1。
- per-rRNA progressive voting：3of3 -> 4of5 -> 6of7 -> 7of8。
- fallback 逻辑不变。
- 输出 TSV 列不变。

### 3.5 删除 `bin/default_count_sam_primary.sh`

用户已明确要求删除该遗留文件。

删除后检查：

```bash
rg -n "default_count_sam_primary"
```

预期无结果。

### 3.6 README 和帮助信息

同步更新：

- `README.md`
- `README_zh.md`
- `bin/resolveS` 的 `print_usage()`

必须覆盖：

- single-end FASTQ：`resolveS -1 sample.fastq.gz`
- paired-end FASTQ：`resolveS -1 R1.fastq.gz -2 R2.fastq.gz`
- single-end SAM：`resolveS -a aligned.sam -m 1`
- paired-end SAM：`resolveS -a aligned.sam -m 2`
- batch SAM 也需要 `-m 1|2`
- `-m` 只用于 SAM 输入
- `-p` 和 `-u` 对 SAM 输入无效，会 warning
- `-u` 对 single-end 表示 reads，对 paired-end 表示 read pairs

## 4. 测试方案

### 4.1 静态检查

运行：

```bash
bash -n bin/resolveS
bash -n bin/default_align_by_bowtie2.sh
bash -n bin/default_align_single_by_bowtie2.sh
perl -c bin/default_counting_withChrom.pl
perl -c bin/auto_counting_withChrom.pl
```

`default_counting_withChrom.pl` 不修改，但仍检查，确认没有被误伤。

### 4.2 复用现有测试

运行：

```bash
bash tests/test_binomial_strand_detection.sh
bash examples/test_prealigned_sam.sh
bash examples/test_batch_sam.sh
bash examples/test_batch_fastq.sh
```

现有 SAM 测试如果使用 paired-end synthetic flags，需要补 `-m 2`。

### 4.3 新增 SAM explicit-mode 测试

新增：

```text
tests/test_sam_explicit_modes.sh
```

测试场景：

| 场景 | 命令 | 预期 |
| --- | --- | --- |
| paired SAM 正常 | `resolveS -a paired.sam -m 2` | 成功输出结果 |
| single SAM 正常 | `resolveS -a single.sam -m 1` | 成功输出结果 |
| SAM 缺少 `-m` | `resolveS -a paired.sam` | 失败，提示需要 `-m` |
| paired SAM 误用 `-m 1` | `resolveS -a paired.sam -m 1` | 失败，提示 use `-m 2` |
| single SAM 误用 `-m 2` | `resolveS -a single.sam -m 2` | 失败，提示 use `-m 1` |
| `-a` 加 `-p/-u` | `resolveS -a paired.sam -m 2 -p 8 -u 1` | 成功，stderr 有 ignored warning |

paired synthetic SAM flags：

```text
forward R1: 67
reverse R1: 83
```

single synthetic SAM flags：

```text
forward: 0
reverse: 16
```

### 4.4 FASTQ 到输出端集成测试

新增：

```text
examples/test_fastq_end_to_end.sh
```

使用以下数据：

single-end：

```text
/mnt/yusim/dalang/projects/wnt_act_data/raw_data/GSE103492/raw/SRR6006665.fastq.gz
```

paired-end：

```text
/mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_1.fastq.gz
/mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_2.fastq.gz
```

测试产物保存到：

```text
examples/test_outputs/
```

建议结构：

```text
examples/test_outputs/
├── single_fastq/
│   ├── stdout.tsv
│   ├── stderr.log
│   ├── result.tsv
│   └── resolveS.sam
├── pair_fastq/
│   ├── stdout.tsv
│   ├── stderr.log
│   ├── result.tsv
│   └── resolveS.sam
├── single_sam/
│   ├── stdout.tsv
│   └── stderr.log
└── pair_sam/
    ├── stdout.tsv
    └── stderr.log
```

FASTQ test 命令使用 `-d` 保留 SAM：

```bash
(
  cd examples/test_outputs/single_fastq
  ../../../bin/resolveS \
    -1 /mnt/yusim/dalang/projects/wnt_act_data/raw_data/GSE103492/raw/SRR6006665.fastq.gz \
    -u 1 -p 3 -d -o result.tsv \
    > stdout.tsv 2> stderr.log
)
```

```bash
(
  cd examples/test_outputs/pair_fastq
  ../../../bin/resolveS \
    -1 /mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_1.fastq.gz \
    -2 /mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_2.fastq.gz \
    -u 1 -p 3 -d -o result.tsv \
    > stdout.tsv 2> stderr.log
)
```

验收：

- `result.tsv` 存在且至少 2 行。
- 第 2 行 `Strand_Type` 非空。
- `MAPQ_Filter` 为 `MAPQ-20/10/3/1` 之一。
- FASTQ case 的 `resolveS.sam` 存在且非空。

### 4.5 batch 测试

新增或更新 metadata：

```text
examples/batch_single_fastq_metadata.txt
examples/batch_pair_fastq_metadata.txt
examples/batch_single_sam_metadata.txt
examples/batch_pair_sam_metadata.txt
```

验收命令：

```bash
bin/resolveS -b examples/batch_single_fastq_metadata.txt -u 1 -p 3
bin/resolveS -b examples/batch_pair_fastq_metadata.txt -u 1 -p 3
bin/resolveS -b examples/batch_single_sam_metadata.txt -m 1
bin/resolveS -b examples/batch_pair_sam_metadata.txt -m 2
```

错误场景：

- SAM batch 不传 `-m` 应失败。
- FASTQ batch 传 `-m` 应失败。
- metadata 混合 1 列 FASTQ 和 1 列 SAM 应失败。
- metadata 混合 1 列和 2 列应失败。

## 5. 验收标准

实现完成后必须满足：

- `resolveS -1 sample.fastq.gz` 能完成 single-end FASTQ 分析。
- `resolveS -1 R1.fastq.gz -2 R2.fastq.gz` 保持 paired-end FASTQ 可用。
- `resolveS -a single.sam -m 1` 可用。
- `resolveS -a paired.sam -m 2` 可用。
- `resolveS -a aligned.sam` 缺少 `-m` 时清晰报错。
- `-p/-u` 在 SAM 输入中被显式 warning 为 ignored。
- batch 模式不会因为单个样本失败而直接退出，能统计 success/failed。
- batch FASTQ 样本不会互相覆盖 SAM 文件。
- paired 和 single alignment 都使用 `--no-unal`。
- `bin/default_counting_withChrom.pl` 没有被修改。
- `bin/auto_counting_withChrom.pl` 存在并被主流程调用。
- `bin/default_count_sam_primary.sh` 已删除且无引用。
- README 中英文同步更新。
- `examples/test_outputs/` 保存 FASTQ 端到输出端测试产物。
- 所有静态检查、SAM explicit-mode 测试、FASTQ end-to-end 测试通过。

## 6. 推荐实现顺序

1. 复制 `bin/default_counting_withChrom.pl` 为 `bin/auto_counting_withChrom.pl`，加入必填 `single|pair` mode 和 SAM mode validation。
2. 新增 `bin/default_align_single_by_bowtie2.sh`。
3. 修改 `bin/default_align_by_bowtie2.sh`：增加 `[output_sam]` 参数和 `--no-unal`。
4. 修改 `bin/resolveS`：
   - 增加 `-m`。
   - 替换旧 `MODE` 为 `INPUT_KIND`。
   - 增加 batch kind 检测。
   - 接入 single FASTQ 和 explicit SAM mode。
   - 修正 batch 错误处理。
   - 修正 batch SAM 路径覆盖问题。
5. 删除 `bin/default_count_sam_primary.sh` 并确认无引用。
6. 更新 `README.md`、`README_zh.md` 和 `resolveS -h`。
7. 新增/更新 tests 和 examples。
8. 运行完整测试。
9. 检查 `git diff`，确认没有误改旧 Perl 和无关文件。

