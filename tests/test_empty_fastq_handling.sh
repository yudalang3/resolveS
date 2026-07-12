#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/resolveS_empty_fastq.XXXXXX")"
EXPECTED_HEADER=$'File\tStrand_Type\tCompatible_Strand_Type\tMAPQ_Filter\tDetection_Level\tOverall_fallback_Fwd\tOverall_fallback_Rev\tOverall_fallback_Fwd_Ratio\tOverall_fallback_Rev_Ratio\tOverall_fallback_Rel_Diff'

assert_output_schema() {
    local output="$1"

    if [[ "$(head -n 1 "$output")" != "$EXPECTED_HEADER" ]]; then
        echo "FAIL: unexpected output header: $output" >&2
        cat "$output" >&2
        return 1
    fi

    if ! awk -F '\t' 'NF != 10 { exit 1 }' "$output"; then
        echo "FAIL: output must contain exactly 10 columns: $output" >&2
        cat "$output" >&2
        return 1
    fi
}

write_unalignable_fastq() {
    local path="$1"

    printf '@read1\nNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN\n+\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n' > "$path"
}

write_matching_fastq() {
    local path="$1"
    local sequence=""
    local line

    while IFS= read -r line; do
        if [[ "$line" == '>'* ]]; then
            [[ -n "$sequence" ]] && break
            continue
        fi
        sequence+="$line"
        [[ "${#sequence}" -ge 75 ]] && break
    done < <("$REPO_ROOT/bowtie2/bowtie2-inspect" "$REPO_ROOT/ref_default/default")

    if [[ "${#sequence}" -lt 50 ]]; then
        echo "FAIL: could not extract a matching read from the default index" >&2
        return 1
    fi

    sequence="${sequence:0:75}"
    printf '@read1\n%s\n+\n%s\n' "$sequence" "${sequence//?/I}" > "$path"
}

assert_fastq_failure() {
    local run_dir="$1"
    shift

    mkdir -p "$run_dir"
    if (
        cd "$run_dir"
        "$REPO_ROOT/bin/resolveS" "$@" > stdout.tsv 2> stderr.log
    ); then
        echo "FAIL: FASTQ input with no alignments unexpectedly succeeded" >&2
        cat "$run_dir/stdout.tsv" >&2
        cat "$run_dir/stderr.log" >&2
        return 1
    fi

    grep -Fq "No alignment records were produced from the FASTQ input." "$run_dir/stderr.log"
    grep -Fq "low rRNA content" "$run_dir/stderr.log"
    grep -Fq "an rRNA reference that does not match the sample" "$run_dir/stderr.log"
    grep -Fq "a -u sampling range that is too small" "$run_dir/stderr.log"
    grep -Fq "The generated SAM file has been kept for diagnosis: resolveS.sam" "$run_dir/stderr.log"

    if grep -Fq "No alignment records found in SAM file" "$run_dir/stderr.log"; then
        echo "FAIL: Perl empty-SAM error leaked to stderr" >&2
        cat "$run_dir/stderr.log" >&2
        return 1
    fi

    if [[ ! -f "$run_dir/resolveS.sam" ]]; then
        echo "FAIL: diagnostic SAM was not retained: $run_dir/resolveS.sam" >&2
        return 1
    fi

    if [[ "$(awk 'END { print NR }' "$run_dir/stdout.tsv")" -ne 1 ]]; then
        echo "FAIL: failed FASTQ output should contain only the header" >&2
        cat "$run_dir/stdout.tsv" >&2
        return 1
    fi

    assert_output_schema "$run_dir/stdout.tsv"
}

assert_normal_fastq_succeeds() {
    local fastq="$1"
    local run_dir="$2"

    mkdir -p "$run_dir"
    (
        cd "$run_dir"
        "$REPO_ROOT/bin/resolveS" -1 "$fastq" -u 1 -p 1 -d > stdout.tsv 2> stderr.log
    )

    if [[ "$(awk 'END { print NR }' "$run_dir/stdout.tsv")" -ne 2 ]]; then
        echo "FAIL: normal FASTQ output should contain a header and one result" >&2
        cat "$run_dir/stdout.tsv" >&2
        return 1
    fi

    if [[ ! -s "$run_dir/resolveS.sam" ]]; then
        echo "FAIL: debug mode did not retain a non-empty SAM" >&2
        return 1
    fi

    assert_output_schema "$run_dir/stdout.tsv"
}

SINGLE_FASTQ="$TMP_DIR/single.fastq"
PAIR_R1="$TMP_DIR/pair_R1.fastq"
PAIR_R2="$TMP_DIR/pair_R2.fastq"
MATCHING_FASTQ="$TMP_DIR/matching.fastq"
write_unalignable_fastq "$SINGLE_FASTQ"
write_unalignable_fastq "$PAIR_R1"
write_unalignable_fastq "$PAIR_R2"
write_matching_fastq "$MATCHING_FASTQ"

assert_fastq_failure "$TMP_DIR/single_run" -1 "$SINGLE_FASTQ" -u 1 -p 1
assert_fastq_failure "$TMP_DIR/pair_run" -1 "$PAIR_R1" -2 "$PAIR_R2" -u 1 -p 1 -d
assert_normal_fastq_succeeds "$MATCHING_FASTQ" "$TMP_DIR/normal_run"

echo "Empty FASTQ handling tests passed"
echo "Temporary test files retained at: $TMP_DIR" >&2
