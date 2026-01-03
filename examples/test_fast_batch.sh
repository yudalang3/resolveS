#!/bin/bash
# Test resolveS_fast batch mode
# Uses -b option to process multiple R1 FASTQ files from metadata file
# Note: Metadata file contains only R1 paths, one per line

cd "$(dirname "$0")"

../bin/resolveS_fast \
  -b batch_fast_metadata.txt \
  -u 1 \
  -p 3
