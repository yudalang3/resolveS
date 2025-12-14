# resolveS: 快速检测 RNA-Seq 链特异性

[English](README.md) | [中文](README_zh.md)

本工具的目标是"快速检测 RNA-Seq 链特异性"。


准确判定链特异性（有链特异性 vs. 无链特异性）是转录组分析的关键前提。它是配置 featureCounts 和 Trinity 等重要生物信息学工具的必要参数。然而，这一信息在公共数据集中往往缺失或标注错误，可能导致结果重现性问题和错误解读。

resolveS 是一款旨在即时解决这一问题的高性能工具。它**超快速、低内存占用**且用户友好，是任何 RNA-Seq 质量控制（QC）流程的完美补充。无论您是探索公共数据还是验证自己的文库，resolveS 都能提供必要的元数据，确保下游分析的准确性和可重复性。

# 安装说明 & 使用指导

首先，请从 **releases** 部分下载压缩包文件。根据您现有的环境，按照以下说明进行软件安装。

请参阅 $ resolveS -h 以获取有关版本和用法的更多信息。

---

## 1. 开箱即用：一站式服务

如果您偏好 `一步到位的解决方案`，不想安装任何依赖，任何环境都想直接能运行。

那么就下载`resolveS_singularity_v0.0.x.sif` 或者 ` resolveS_apptainer_v0.0.x.sif`。这是一套即用型且省时的 `解决方案`。无需安装任何东西！

如果您希望获得开箱即用的软件，不想安装任何复杂的依赖：

```bash
# 在容器内运行默认命令
singularity run /path/to/resolveS_singularity_v0.0.1.sif -s 1_fastq.gz
#### Or ####
# 在容器内直接执行 'resolveS' 命令
singularity exec resolveS_v0.0.1.sif resolveS
```


## 2. 绿色免安装版本 portable_program

如果您不想了解容器的使用，想直接使用软件，且不想安装任何依赖，可以使用免安装版本。

那么就下载 `portable_program_v0.0.x.tar.gz`，然后解压 `tar -xvf ...`

得到以下的程序，解压之后的内容如下：

```
resolveS
├── LICENSE
├── README.md
├── README_zh.md
├── benchmark
│   ├── benchmark_test.sh
│   ├── input.batch.run.txt
│   └── results.tsv
├── bin
│   ├── align_by_bowtie2.sh
│   ├── check_strand.py
│   ├── count_sam.sh
│   ├── resolveS
│   └── resolveS_sensitive
├── bowtie2
```

使用方法：

```bash
./resolveS/bin/resolveS -s ~/project/xxxx/0h_1A/0h_1A_1.fq.gz
#[INFO] Processing: /home/dell/project/xxx/0h_1A/0h_1A_1.fq.gz (threads: 6, max_alig_reads: 1000000, reference: /mnt/c/Users/yudal/Documents/resolveS/bin/../ref_default/default)
#ls ~/project/xxx 1000000 reads; of these:
#  1000000 (100.00%) were unpaired; of these:
#    991905 (99.19%) aligned 0 times
#    552 (0.06%) aligned exactly 1 time
#    7543 (0.75%) aligned >1 times
#0.81% overall alignment rate
#File    Strandedness    Fwd     Rev     Total   Fwd_Ratio       Rev_Ratio       F2R_Ratio       Log2_F2R        Rel_Diff        Chi2    P_value Cohens_h   Cramers_V       Bayes_Factor    Epsilon Hellinger       Entropy
#/home/dell/project/xxx/0h_1A/0h_1A_1.fq.gz    fr-unstranded   4142    3953    8095    0.511674        0.488326        1.047812        0.067371   0.046695        4.412724        3.567184e-02    0.023350        0.023348        7.905134e+00    0.016512        0.008255        0.999607
#[INFO] Cleaned up temporary file: resolveS.sam
#[INFO] Cleaned up temporary file: log.raw.SAM.counts.txt
#[INFO] All done!
```

将结果保存到文本文件中：


```bash
./resolveS/bin/resolveS -s ~/project/xxxx/0h_1A/0h_1A_1.fq.gz > results.txt
cat results.txt
#File    Strandedness    Fwd     Rev     Total   Fwd_Ratio       Rev_Ratio       F2R_Ratio       Log2_F2R        Rel_Diff        Chi2    P_value Cohens_h   Cramers_V       Bayes_Factor    Epsilon Hellinger       Entropy
#/home/dell/project/xxx/0h_1A/0h_1A_1.fq.gz    fr-unstranded   4142    3953    8095    0.511674        0.488326        1.047812        0.067371   0.046695        4.412724        3.567184e-02    0.023350        0.023348        7.905134e+00    0.016512        0.008255        0.999607
```

最终，`Strandedness` 一列就是推断的结果。

-b 参数可以批量运行。

## 1. 如果您已安装 **Bowtie 2** 和 **Python 3**

只需解压下载的压缩包。然后，您可以直接运行名为 `resolveS` 的可执行文件。如果希望从任何目录执行它，可以将此文件添加到系统的 `PATH` 环境变量中。

> 您还需要从 `https://github.com/yudalang3/resolveS/releases` 下载 bowtie2 索引文件。

最终的程序结构应如下所示：

```
resolveS/
├── align_by_bowtie2.sh
├── check_strand.py
├── count_sam.sh
├── ref_bowtie2
│   ├── default.1.bt2
│   ├── default.2.bt2
│   ├── default.3.bt2
│   ├── default.4.bt2
│   ├── default.rev.1.bt2
│   └── default.rev.2.bt2
└── resolveS
```

---

## 3. 如果您偏好使用 **Conda** / **Mamba**

您已经是高级用户了，您可以自行查看 `bin` 目录，修改 `align_by_bowtie2.sh` 配置 `bowtie2` 即可。

> 您还需要下载 bowtie2 索引文件


然后是一般的步骤：

**方法 1：创建并激活环境（推荐）**

```bash
conda/mamba create -n estimate python=3 bowtie2
conda/mamba activate estimate
```

**方法 2：创建环境，然后通过 Bioconda 安装 Bowtie 2**

```
conda/mamba create -n estimate python=3
conda/mamba activate estimate
mamba install bioconda::bowtie2
```

激活环境后，按照上述部分（"如果您已安装 Bowtie 2 和 Python 3"）中描述的安装步骤进行操作。



# 使用方法和输出演示

以 `一步到位的解决方案` 为例：

> `Strandedness` 字段（列）有四个可能的值：fr-unstranded、fr-firststrand、fr-secondstrand 和 insufficient-data。

## 链特异性判定标准

本工具使用三级决策流程来判定链特异性：

1. **总数检查（Total > 3000）**
   - 如果总数（正链 + 负链）≤ 3000，结果将为 `insufficient-data`（数据不足）
   - 这确保了有足够的统计能力进行可靠推断

2. **链特异性测试（相对差异 > 1）**
   - 如果相对差异（Rel_Diff）≤ 1，结果将为 `fr-unstranded`（非链特异性）
   - 这表明是非链特异性测序

3. **链方向判定（F2R_Ratio > 1）**
   - 如果 F2R_Ratio > 1，结果将为 `fr-firststrand`（第一链）
   - 否则，结果将为 `fr-secondstrand`（第二链）

这些标准通过过滤低覆盖度样本并正确区分不同的文库制备方案，确保准确可靠的链特异性检测。

```bash
$ time apptainer run /home/dell/projects/estimate_strand4NGS/formal_program/resolveS/db/resolveS_singularity_v0.0.1.sif -s ss/1-1/1-1_1.fq.gz -p 10 > results.tsv
[INFO] Processing: ss/1-1/1-1_1.fq.gz (threads: 10)
4000000 reads; of these:
  4000000 (100.00%) were unpaired; of these:
    3959187 (98.98%) aligned 0 times
    2686 (0.07%) aligned exactly 1 time
    38127 (0.95%) aligned >1 times
1.02% overall alignment rate
[INFO] Cleaned up temporary file: resolveS.sam
[INFO] Cleaned up temporary file: log.raw.SAM.counts.txt
[INFO] All done!
apptainer run  -s ss/1-1/1-1_1.fq.gz -p 10 > results.tsv  82.14s user 1.27s system 803% cpu 10.388 total
(base)
# dell @ dell-Precision-3660 in /home/dell/projects/estimate_strand4NGS/test_data1 [12:28:15]
$ cat results.tsv
File    Strandedness    Fwd     Rev     Total   Fwd_Ratio       Rev_Ratio       F2R_Ratio       Log2_F2R        Rel_Diff        Chi2    P_value Cohens_h        Cramers_V       Bayes_Factor        Epsilon Hellinger       Entropy
/home/dell/projects/estimate_strand4NGS/test_data1/ss/1-1/1-1_1.fq.gz   fr-secondstrand   3117    37696   40813   0.076373        0.923627        0.082688        -3.595969       1.694509    29297.215128    0.000000e+00    -1.010795       0.847255        0.000000e+00    0.748243        0.353579        0.389267

```

对于最终用户来说，`一步到位的解决方案` 是使用 resolveS 最方便的方式。
您可以重点关注输出 tsv 文件中的 `File` 和 `Strandedness` 两列。

# 完整程序文档

## 参数说明

### 单文件运行模式：
- `-h`, `--help`：显示帮助信息并退出。
- `-s <file>`：输入 fastq 文件。
- `-p <int>`：线程数（默认：6）。
- `-u <number>`：比对的最大 reads 数量（默认：1000000）。
- `-r <path>`：参考基因组数据库路径，可以是任何 bowtie2 索引（默认：../ref_default/default）。
- `-c <file>`：从 SAM 文件输出计数矩阵（默认：log.raw.SAM.counts.txt）调试选项。

### 批量文件运行模式：
- `-h`, `--help`：显示帮助信息并退出。
- `-b <meta_data_file>`：包含一列 fastq 文件路径的元数据文件。
- `-p <int>`：线程数（默认：6）。
- `-u <number>`：比对的最大 reads 数量（默认：1000000）。
- `-r <path>`：参考基因组数据库路径，可以是任何 bowtie2 索引（默认：../ref_default/default）。
- `-c <file>`：从 SAM 文件输出计数矩阵（默认：log.raw.SAM.counts.txt）调试选项。
