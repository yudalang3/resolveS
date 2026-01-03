#!/bin/bash
# Test resolveS batch mode with FASTQ files
# Uses -b option to process multiple paired-end samples from metadata file

../bin/resolveS \
  -b data/batch_fastq_metadata.txt \
  -u 1 \
  -p 3
