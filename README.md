# resolveS: Rapid RNA-Seq Strand Specificity Detection

[English](README.md) | [中文](README_zh.md)

The goal of this tool is "Rapid RNA-Seq Strand Specificity Detection".


Accurate determination of strand specificity (stranded vs. non-stranded) is a critical prerequisite for transcriptomic analysis. It is a necessary parameter for configuring essential bioinformatics tools like featureCounts and Trinity. However, this information is often missing or incorrectly annotated in public datasets, which can lead to reproducibility issues and misinterpretation of results.

resolveS is a high-performance tool designed to solve this problem instantly. It is **super-fast, memory-efficient**, and user-friendly, making it the perfect addition to any RNA-Seq Quality Control (QC) pipeline. Whether you are exploring public data or validating your own libraries, resolveS provides the necessary metadata to ensure your downstream analysis is accurate and reproducible.

# Installation & Current Version

To begin, please download the archive file from the **releases** section. Follow the instructions below based on your existing environment to proceed with the software installation.

If the `./resolveS` file is executable, you can skip the next step. Otherwise, you need to make it executable by running the following command in the terminal:

```bash
chmod +x ./resolveS ./count_sam.sh ./check_strand.py ./align_by_bowtie2.sh
```

Please see the `$ resolveS -h` for more information on the version and usage.

---

## 1. If you already have **Bowtie 2** and **Python 3** installed

Simply extract the downloaded archive. Then, you can directly run the executable file named `resolveS`. If you wish to execute it from any directory, you may add this file to your system's `PATH` environment variable.

> You also need to download the bowtie2 index files at `https://github.com/yudalang3/resolveS/releases`.

The final program structure should be as follows:

```
resolveS/
├── align_by_bowtie2.sh
├── check_strand.py
├── count_sam.sh
├── ref_bowtie2
│   ├── default.1.bt2
│   ├── default.2.bt2
│   ├── default.3.bt2
│   ├── default.4.bt2
│   ├── default.rev.1.bt2
│   └── default.rev.2.bt2
└── resolveS

```

---

## 2. If you prefer using **Conda** / **Mamba**

First, create the required environment using one of the following methods:

**Method 1: Create and Activate Environment (Recommended)**

```bash
conda/mamba create -n estimate python=3 bowtie2
conda/mamba activate estimate
```

**Method 2: Create Environment, then Install Bowtie 2 via Bioconda**

```
conda/mamba create -n estimate python=3
conda/mamba activate estimate
mamba install bioconda::bowtie2
```

After activating the environment, proceed with the installation steps as described in the section above ("If you already have Bowtie 2 and Python 3 installed").

> You also need to download the bowtie2 index files

## 3. If you prefer `a one-step solution`

This is a ready-to-use and time-saving `solution`. No need to install anything!

We provide a Singularity (or Apptainer) container for ease of use. You can download the image file directly and run it:

> All you need is the Singularity (or Apptainer) container file. DO NOT need to download bowtie2 index anymore.

```bash
# To run the default command within the container
singularity run /path/to/resolveS_singularity_v0.0.1.sif -s 1_fastq.gz

# To execute the 'resolveS' command directly within the container
singularity exec resolveS_v0.0.1.sif resolveS
```

# Usage and output demonstration

Take the `one-step solution` as an example:

> The `Strandedness` field(column) has three possible values: fr-unstranded, fr-firststrand, fr-secondstrand.

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

For the end-user, the `one-step solution` is the most convenient way to use resolveS.
And you can focus on the `File` and `Strandedness` columns in the output tsv file.

# Full program documentation

## Parameters explanation

### Single file runnning mode:
- `-h`, `--help`: Show help message and exit.
- `-s <file>`: Input fastq file.
- `-p <int>`: Number of threads (default: 6).
- `-u <number>`: Maximum number of reads to align (default: 4000000).
- `-o <output_file>`: Output file (default: stdout).

### Batch file running mode:
- `-h`, `--help`: Show help message and exit.
- `-b <meta_data_file>`: A meta data file with one column of fastq file paths.
- `-p <int>`: Number of threads (default: 6).
- `-u <number>`: Maximum number of reads to align (default: 4000000).
- `-o <output_file>`: Output file (default: stdout).
