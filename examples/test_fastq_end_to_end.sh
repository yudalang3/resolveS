#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_ROOT="$SCRIPT_DIR/test_outputs"

SINGLE_READ="/mnt/yusim/dalang/projects/wnt_act_data/raw_data/GSE103492/raw/SRR6006665.fastq.gz"
PAIR_R1="/mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_1.fastq.gz"
PAIR_R2="/mnt/yusim/dalang/projects/resolveS/data/Signal_2022/raw/SRR9844293_2.fastq.gz"

validate_result() {
    local result_file="$1"
    local sam_file="${2:-}"
    local line_count
    local strand_type
    local mapq_filter

    if [[ ! -s "$result_file" ]]; then
        echo "FAIL: result file missing or empty: $result_file" >&2
        return 1
    fi

    line_count="$(awk 'END { print NR }' "$result_file")"
    if [[ "$line_count" -lt 2 ]]; then
        echo "FAIL: result file has fewer than 2 lines: $result_file" >&2
        cat "$result_file" >&2
        return 1
    fi

    strand_type="$(awk 'NR == 2 { print $2 }' "$result_file")"
    mapq_filter="$(awk 'NR == 2 { print $3 }' "$result_file")"

    if [[ -z "$strand_type" ]]; then
        echo "FAIL: empty Strand_Type in $result_file" >&2
        cat "$result_file" >&2
        return 1
    fi

    if [[ ! "$mapq_filter" =~ ^MAPQ-(20|10|3|1)$ ]]; then
        echo "FAIL: unexpected MAPQ_Filter '$mapq_filter' in $result_file" >&2
        cat "$result_file" >&2
        return 1
    fi

    if [[ -n "$sam_file" && ! -s "$sam_file" ]]; then
        echo "FAIL: expected non-empty SAM file: $sam_file" >&2
        return 1
    fi
}

for input_file in "$SINGLE_READ" "$PAIR_R1" "$PAIR_R2"; do
    if [[ ! -f "$input_file" ]]; then
        echo "FAIL: required FASTQ file not found: $input_file" >&2
        exit 1
    fi
done

mkdir -p "$OUT_ROOT/single_fastq" "$OUT_ROOT/pair_fastq" "$OUT_ROOT/single_sam" "$OUT_ROOT/pair_sam"

(
    cd "$OUT_ROOT/single_fastq"
    "$REPO_ROOT/bin/resolveS" \
        -1 "$SINGLE_READ" \
        -u 1 -p 3 -d -o result.tsv \
        > stdout.tsv 2> stderr.log
)
validate_result "$OUT_ROOT/single_fastq/result.tsv" "$OUT_ROOT/single_fastq/resolveS.sam"

(
    cd "$OUT_ROOT/pair_fastq"
    "$REPO_ROOT/bin/resolveS" \
        -1 "$PAIR_R1" \
        -2 "$PAIR_R2" \
        -u 1 -p 3 -d -o result.tsv \
        > stdout.tsv 2> stderr.log
)
validate_result "$OUT_ROOT/pair_fastq/result.tsv" "$OUT_ROOT/pair_fastq/resolveS.sam"

(
    cd "$OUT_ROOT/single_sam"
    "$REPO_ROOT/bin/resolveS" \
        -a "$OUT_ROOT/single_fastq/resolveS.sam" -m 1 \
        > stdout.tsv 2> stderr.log
)
validate_result "$OUT_ROOT/single_sam/stdout.tsv"

(
    cd "$OUT_ROOT/pair_sam"
    "$REPO_ROOT/bin/resolveS" \
        -a "$OUT_ROOT/pair_fastq/resolveS.sam" -m 2 \
        > stdout.tsv 2> stderr.log
)
validate_result "$OUT_ROOT/pair_sam/stdout.tsv"

echo "FASTQ end-to-end tests passed"
