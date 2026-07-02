#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$REPO_ROOT/bin/resolveS" \
  -1 /mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_1.fastq.gz \
  -2 /mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_2.fastq.gz \
  -u 1 -p 3
