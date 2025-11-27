# resolveS: Resolve RNA-Seq Strand Specificity

The aim is to "Rapid RNA-Seq Strand Specificity Detection".


Accurate determination of strand specificity (stranded vs. non-stranded) is a critical prerequisite for transcriptomic analysis. It is a vital parameter for configuring essential bioinformatics tools like featureCounts and Trinity. However, this information is often missing in public datasets or requires verification in internal analysis.

resolveS is a high-performance tool designed to solve this problem instantly. It is **super-fast, memory-efficient**, and user-friendly, making it the perfect addition to any RNA-Seq Quality Control (QC) pipeline. Whether you are exploring public data or validating your own libraries, resolveS provides the necessary metadata to ensure your downstream analysis is accurate and reproducible.

# Installation

To begin, please download the archive file from the **releases** section. Follow the instructions below based on your existing environment to proceed with the software installation.

---

## If you already have **Bowtie 2** and **Python 3** installed

Simply extract the downloaded archive. Then, you can directly run the executable file named `resolveS`. If you wish to execute it from any directory, you may add this file to your system's `PATH` environment variable.

---

## If you prefer using **Conda** / **Mamba**

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

## If you prefer a one-step solution

We provide a Singularity (or Apptainer) container for ease of use. You can download the image file directly and run it:

```bash
# To run the default command within the container
singularity run resolveS_v0.0.1.sif

# To execute the 'resolveS' command directly within the container
singularity exec resolveS_v0.0.1.sif resolveS
```