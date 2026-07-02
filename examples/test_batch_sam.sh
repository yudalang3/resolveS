#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$SCRIPT_DIR/test_outputs/batch_sam_inputs"
SINGLE_SAM="$OUT_DIR/single.sam"
PAIR_SAM="$OUT_DIR/pair.sam"

mkdir -p "$OUT_DIR"

{
    printf '@HD\tVN:1.6\tSO:unsorted\n'
    printf '@SQ\tSN:chr1\tLN:1000\n'
    printf '@SQ\tSN:chr2\tLN:1000\n'
    printf '@SQ\tSN:chr3\tLN:1000\n'

    read_id=0
    for chrom in chr1 chr2 chr3; do
        for ((i = 1; i <= 20; i++)); do
            read_id=$((read_id + 1))
            printf 'read%s\t0\t%s\t1\t60\t1M\t*\t0\t0\tA\tI\n' "$read_id" "$chrom"
        done
    done
} > "$SINGLE_SAM"

{
    printf '@HD\tVN:1.6\tSO:unsorted\n'
    printf '@SQ\tSN:chr1\tLN:1000\n'
    printf '@SQ\tSN:chr2\tLN:1000\n'
    printf '@SQ\tSN:chr3\tLN:1000\n'

    read_id=0
    for chrom in chr1 chr2 chr3; do
        for ((i = 1; i <= 20; i++)); do
            read_id=$((read_id + 1))
            printf 'read%s\t67\t%s\t1\t60\t1M\t=\t1\t0\tA\tI\n' "$read_id" "$chrom"
        done
    done
} > "$PAIR_SAM"

(
    cd "$REPO_ROOT"
    "$REPO_ROOT/bin/resolveS" -b "$SCRIPT_DIR/batch_single_sam_metadata.txt" -m 1
    "$REPO_ROOT/bin/resolveS" -b "$SCRIPT_DIR/batch_pair_sam_metadata.txt" -m 2
)
