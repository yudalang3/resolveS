# resolveS: 快速检测 RNA-Seq 链特异性

[English](README.md) | [中文](README_zh.md)

本工具的目标是"快速检测 RNA-Seq 链特异性"。


准确判定链特异性（有链特异性 vs. 无链特异性）是转录组分析的关键前提。它是配置 featureCounts 和 Trinity 等重要生物信息学工具的必要参数。然而,这一信息在公共数据集中往往缺失或标注错误,可能导致结果重现性问题和错误解读。

resolveS 是一款旨在即时解决这一问题的高性能工具。它**超快速、低内存占用**且用户友好,是任何 RNA-Seq 质量控制(QC)流程的完美补充。无论您是探索公共数据还是验证自己的文库,resolveS 都能提供必要的元数据,确保下游分析的准确性和可重复性。

# 安装说明

首先，请从 **releases** 部分下载压缩包文件。根据您现有的环境，按照以下说明进行软件安装。

如果 `./resolveS` 文件已经是可执行的，您可以跳过下一步。否则，您需要通过在终端中运行以下命令使其可执行：

```bash
chmod +x ./resolveS ./count_sam.sh ./check_strand.py ./align_by_bowtie2.sh
```

---

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

## 2. 如果您偏好使用 **Conda** / **Mamba**

首先，使用以下方法之一创建所需的环境：

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

> 您还需要下载 bowtie2 索引文件

## 3. 如果您偏好 `一步到位的解决方案`

这是一套即用型且省时的 `解决方案`。无需安装任何东西！

我们提供了 Singularity（或 Apptainer）容器以便使用。您可以直接下载镜像文件并运行：

> 您只需要 Singularity（或 Apptainer）容器文件。不再需要下载 bowtie2 索引。

```bash
# 在容器内运行默认命令
singularity run /path/to/resolveS_singularity_v0.0.1.sif -s 1_fastq.gz

# 在容器内直接执行 'resolveS' 命令
singularity exec resolveS_v0.0.1.sif resolveS
```

# 使用方法和输出演示

以 `一步到位的解决方案` 为例：

> `Strandedness` 字段（列）有三个可能的值：fr-unstranded、fr-firststrand、fr-secondstrand。

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
- `-o <output_file>`：输出文件（默认：stdout）。

### 批量文件运行模式：
- `-h`, `--help`：显示帮助信息并退出。
- `-b <meta_data_file>`：包含一列 fastq 文件路径的元数据文件。
- `-p <int>`：线程数（默认：6）。
- `-o <output_file>`：输出文件（默认：stdout）。
