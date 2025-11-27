# resolveS: 快速检测 RNA-Seq 链特异性

[English](README.md) | [中文](README_zh.md)

本工具的目标是"快速检测 RNA-Seq 链特异性"。

准确判定链特异性（有链特异性 vs. 无链特异性）是转录组分析的关键前提。它是配置 featureCounts 和 Trinity 等重要生物信息学工具的必要参数。然而，这一信息在公共数据集中往往缺失，或在内部分析中需要验证。

resolveS 是一款高性能工具，旨在即时解决这一问题。它**超快速、低内存占用**且用户友好，是任何 RNA-Seq 质量控制（QC）流程的完美补充。无论您是探索公共数据还是验证自己的文库，resolveS 都能提供必要的元数据，确保下游分析的准确性和可重复性。

# 安装说明

首先，请从 **releases** 部分下载压缩包文件。根据您现有的环境，按照以下说明进行软件安装。

如果 `./resolveS` 文件已经是可执行的，您可以跳过下一步。否则，您需要通过在终端中运行以下命令使其可执行：

```bash
chmod +x ./resolveS ./count_sam.sh ./check_strand.py ./align_by_bowtie2.sh
```

---

## 如果您已安装 **Bowtie 2** 和 **Python 3**

只需解压下载的压缩包。然后，您可以直接运行名为 `resolveS` 的可执行文件。如果希望从任何目录执行它，可以将此文件添加到系统的 `PATH` 环境变量中。

---

## 如果您偏好使用 **Conda** / **Mamba**

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

## 如果您偏好一步到位的解决方案

这是一套即用型且省时的解决方案。无需安装任何东西！

我们提供了 Singularity（或 Apptainer）容器以便使用。您可以直接下载镜像文件并运行：

```bash
# 在容器内运行默认命令
singularity run resolveS_v0.0.1.sif

# 在容器内直接执行 'resolveS' 命令
singularity exec resolveS_v0.0.1.sif resolveS
```
