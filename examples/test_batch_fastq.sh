#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test resolveS batch mode with single-end and paired-end FASTQ metadata.
"$REPO_ROOT/bin/resolveS" \
  -b "$SCRIPT_DIR/batch_single_fastq_metadata.txt" \
  -u 1 \
  -p 3

"$REPO_ROOT/bin/resolveS" \
  -b "$SCRIPT_DIR/batch_pair_fastq_metadata.txt" \
  -u 1 \
  -p 3
