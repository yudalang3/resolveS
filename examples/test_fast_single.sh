#!/bin/bash
# Test resolveS_fast single file mode
# Uses -s option to process one R1 FASTQ file
# Note: Only provide R1 file, not R2

cd "$(dirname "$0")"

../bin/resolveS_fast \
  -s data/0h_1A_1.fq.gz \
  -u 1 \
  -p 3
