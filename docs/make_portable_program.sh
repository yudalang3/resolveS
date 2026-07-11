#!/bin/bash

VERSION="0.2.2"

#tar -cvf "resolveS_portable_v${VERSION}.tar" \
tar -cvJf "resolveS_portable_v${VERSION}.tar.xz" \
    --exclude='resolveS/db' \
    --exclude='resolveS/docs' \
    --exclude='resolveS/.git' \
    --exclude='resolveS/.gitignore' \
    --exclude='resolveS/ref_sensitive' \
    --exclude='resolveS/tests' \
    --exclude='resolveS/examples' \
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
