#!/bin/bash

tar -cvJf resolveS_portable_v0.0.6.tar.xz \
    --exclude='resolveS/db' \
    --exclude='resolveS/docs' \
    --exclude='resolveS/.git' \
    --exclude='resolveS/.gitignore' \
    --exclude='resolveS/ref_sensitive' \
    --exclude='resolveS/bowtie2/*-debug' \
    --exclude='resolveS/bowtie2/example' \
    --exclude='resolveS/bowtie2/doc' \
    --exclude='resolveS/bowtie2/scripts' \
    --exclude='resolveS/bowtie2/MANUAL' \
    --exclude='resolveS/bowtie2/MANUAL.markdown' \
    --exclude='resolveS/bowtie2/README.md' \
    --exclude='resolveS/bowtie2/NEWS' \
    --exclude='resolveS/bowtie2/TUTORIAL' \
    --exclude='resolveS/bowtie2/AUTHORS' \
    resolveS/
