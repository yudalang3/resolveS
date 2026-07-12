#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/resolveS_sam_modes.XXXXXX")"

write_paired_sam() {
    local path="$1"

    {
        printf '@HD\tVN:1.6\tSO:unsorted\n'
        printf '@SQ\tSN:chr1\tLN:1000\n'
        printf '@SQ\tSN:chr2\tLN:1000\n'
        printf '@SQ\tSN:chr3\tLN:1000\n'

        local read_id=0
        local chrom
        local i
        for chrom in chr1 chr2 chr3; do
            for ((i = 1; i <= 20; i++)); do
                read_id=$((read_id + 1))
                printf 'read%s\t67\t%s\t1\t60\t1M\t=\t1\t0\tA\tI\n' "$read_id" "$chrom"
            done
        done
    } > "$path"
}

write_single_sam() {
    local path="$1"

    {
        printf '@HD\tVN:1.6\tSO:unsorted\n'
        printf '@SQ\tSN:chr1\tLN:1000\n'
        printf '@SQ\tSN:chr2\tLN:1000\n'
        printf '@SQ\tSN:chr3\tLN:1000\n'

        local read_id=0
        local chrom
        local i
        for chrom in chr1 chr2 chr3; do
            for ((i = 1; i <= 20; i++)); do
                read_id=$((read_id + 1))
                printf 'read%s\t0\t%s\t1\t60\t1M\t*\t0\t0\tA\tI\n' "$read_id" "$chrom"
            done
        done
    } > "$path"
}

assert_success_output() {
    local stdout="$1"
    local expected_strand_type="$2"
    local expected_compatible_type="$3"
    local strand_type
    local compatible_type
    local mapq_filter

    strand_type="$(awk 'NR == 2 { print $2 }' "$stdout")"
    compatible_type="$(awk 'NR == 2 { print $3 }' "$stdout")"
    mapq_filter="$(awk 'NR == 2 { print $4 }' "$stdout")"

    if [[ "$strand_type" != "$expected_strand_type" ]]; then
        echo "FAIL: expected Strand_Type '$expected_strand_type', got '$strand_type' in $stdout" >&2
        cat "$stdout" >&2
        return 1
    fi

    if [[ "$compatible_type" != "$expected_compatible_type" ]]; then
        echo "FAIL: expected Compatible_Strand_Type '$expected_compatible_type', got '$compatible_type' in $stdout" >&2
        cat "$stdout" >&2
        return 1
    fi

    if [[ ! "$mapq_filter" =~ ^MAPQ-(20|10|3|1)$ ]]; then
        echo "FAIL: unexpected MAPQ_Filter '$mapq_filter' in $stdout" >&2
        cat "$stdout" >&2
        return 1
    fi

    if awk -F '\t' 'NF != 10 { exit 1 }' "$stdout"; then
        :
    else
        echo "FAIL: output must contain exactly 10 columns: $stdout" >&2
        cat "$stdout" >&2
        return 1
    fi
}

assert_fails_with() {
    local expected="$1"
    shift

    local stdout="$TMP_DIR/fail.stdout"
    local stderr="$TMP_DIR/fail.stderr"

    if "$@" > "$stdout" 2> "$stderr"; then
        echo "FAIL: command unexpectedly succeeded: $*" >&2
        cat "$stdout" >&2
        cat "$stderr" >&2
        return 1
    fi

    if ! grep -Fq "$expected" "$stderr"; then
        echo "FAIL: expected stderr to contain: $expected" >&2
        cat "$stderr" >&2
        return 1
    fi
}

assert_empty_sam_fails_cleanly() {
    local sam_file="$1"
    local case_name="$2"
    local stdout="$TMP_DIR/${case_name}.stdout"
    local stderr="$TMP_DIR/${case_name}.stderr"

    if "$REPO_ROOT/bin/resolveS" -a "$sam_file" -m 1 > "$stdout" 2> "$stderr"; then
        echo "FAIL: empty SAM unexpectedly succeeded: $sam_file" >&2
        cat "$stdout" >&2
        cat "$stderr" >&2
        return 1
    fi

    grep -Fq "The provided SAM file contains no alignment records: $sam_file" "$stderr"
    grep -Fq "Check whether the file is empty, contains only headers, or was not generated correctly." "$stderr"

    if grep -Fq "No alignment records found in SAM file" "$stderr"; then
        echo "FAIL: Perl empty-SAM error leaked to stderr: $sam_file" >&2
        cat "$stderr" >&2
        return 1
    fi

    if [[ "$(awk 'END { print NR }' "$stdout")" -ne 1 ]]; then
        echo "FAIL: empty SAM output should contain only the header: $sam_file" >&2
        cat "$stdout" >&2
        return 1
    fi
}

PAIRED_SAM="$TMP_DIR/paired.sam"
SINGLE_SAM="$TMP_DIR/single.sam"
write_paired_sam "$PAIRED_SAM"
write_single_sam "$SINGLE_SAM"

"$REPO_ROOT/bin/resolveS" -a "$PAIRED_SAM" -m 2 > "$TMP_DIR/paired.stdout" 2> "$TMP_DIR/paired.stderr"
assert_success_output "$TMP_DIR/paired.stdout" fr-secondstrand fr-secondstrand

"$REPO_ROOT/bin/resolveS" -a "$SINGLE_SAM" -m 1 > "$TMP_DIR/single.stdout" 2> "$TMP_DIR/single.stderr"
assert_success_output "$TMP_DIR/single.stdout" forward-stranded fr-secondstrand

assert_fails_with "SAM input requires -m" "$REPO_ROOT/bin/resolveS" -a "$PAIRED_SAM"
assert_fails_with "use -m 2" "$REPO_ROOT/bin/resolveS" -a "$PAIRED_SAM" -m 1
assert_fails_with "use -m 1" "$REPO_ROOT/bin/resolveS" -a "$SINGLE_SAM" -m 2

"$REPO_ROOT/bin/resolveS" -a "$PAIRED_SAM" -m 2 -p 8 -u 1 > "$TMP_DIR/warn.stdout" 2> "$TMP_DIR/warn.stderr"
assert_success_output "$TMP_DIR/warn.stdout" fr-secondstrand fr-secondstrand
grep -Fq "[WARN] -p is ignored for SAM input because no alignment is run" "$TMP_DIR/warn.stderr"
grep -Fq "[WARN] -u is ignored for SAM input because no alignment is run" "$TMP_DIR/warn.stderr"

EMPTY_SAM="$TMP_DIR/empty.sam"
HEADER_ONLY_SAM="$TMP_DIR/header_only.sam"
HEADER_BLANK_SAM="$TMP_DIR/header_blank.sam"
MINIMAL_SAM="$TMP_DIR/minimal.sam"

: > "$EMPTY_SAM"
printf '@HD\tVN:1.6\tSO:unsorted\n@SQ\tSN:chr1\tLN:1000\n' > "$HEADER_ONLY_SAM"
printf '@HD\tVN:1.6\tSO:unsorted\n\n   \n' > "$HEADER_BLANK_SAM"
printf 'read1\t0\n' > "$MINIMAL_SAM"

assert_empty_sam_fails_cleanly "$EMPTY_SAM" "empty"
assert_empty_sam_fails_cleanly "$HEADER_ONLY_SAM" "header_only"
assert_empty_sam_fails_cleanly "$HEADER_BLANK_SAM" "header_blank"

"$REPO_ROOT/bin/resolveS" -a "$MINIMAL_SAM" -m 1 > "$TMP_DIR/minimal.stdout" 2> "$TMP_DIR/minimal.stderr"
assert_success_output "$TMP_DIR/minimal.stdout" insufficient-data insufficient-data

BATCH_METADATA="$TMP_DIR/batch_sam_metadata.txt"
printf '%s\n%s\n' "$EMPTY_SAM" "$SINGLE_SAM" > "$BATCH_METADATA"

if "$REPO_ROOT/bin/resolveS" -b "$BATCH_METADATA" -m 1 > "$TMP_DIR/batch.stdout" 2> "$TMP_DIR/batch.stderr"; then
    echo "FAIL: SAM batch with an empty sample unexpectedly succeeded" >&2
    cat "$TMP_DIR/batch.stdout" >&2
    cat "$TMP_DIR/batch.stderr" >&2
    exit 1
fi

grep -Fq "Failed to process sample 1: $EMPTY_SAM" "$TMP_DIR/batch.stderr"
grep -Fq "Total: 2 | Success: 1 | Failed: 1" "$TMP_DIR/batch.stderr"
if grep -Fq "No alignment records found in SAM file" "$TMP_DIR/batch.stderr"; then
    echo "FAIL: Perl empty-SAM error leaked during batch processing" >&2
    cat "$TMP_DIR/batch.stderr" >&2
    exit 1
fi
if [[ "$(awk 'END { print NR }' "$TMP_DIR/batch.stdout")" -ne 2 ]]; then
    echo "FAIL: SAM batch output should contain one header and one successful result" >&2
    cat "$TMP_DIR/batch.stdout" >&2
    exit 1
fi
assert_success_output "$TMP_DIR/batch.stdout" forward-stranded fr-secondstrand

echo "SAM explicit mode tests passed"
echo "Temporary test files retained at: $TMP_DIR" >&2
