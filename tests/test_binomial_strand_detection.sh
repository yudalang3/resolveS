#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_sam() {
    local path="$1"
    shift

    {
        printf '@HD\tVN:1.6\tSO:unsorted\n'

        local spec
        for spec in "$@"; do
            IFS=: read -r chrom _f _r <<< "$spec"
            printf '@SQ\tSN:%s\tLN:1000\n' "$chrom"
        done

        local read_id=0
        for spec in "$@"; do
            IFS=: read -r chrom fwd rev <<< "$spec"

            local i
            for ((i = 1; i <= fwd; i++)); do
                read_id=$((read_id + 1))
                printf 'read%s\t67\t%s\t1\t60\t1M\t=\t1\t0\tA\tI\n' "$read_id" "$chrom"
            done

            for ((i = 1; i <= rev; i++)); do
                read_id=$((read_id + 1))
                printf 'read%s\t83\t%s\t1\t60\t1M\t=\t1\t0\tA\tI\n' "$read_id" "$chrom"
            done
        done
    } > "$path"
}

run_case() {
    local name="$1"
    local expected_type="$2"
    shift 2

    local sam="$TMP_DIR/${name}.sam"
    local stdout="$TMP_DIR/${name}.stdout"
    local stderr="$TMP_DIR/${name}.stderr"

    write_sam "$sam" "$@"
    "$REPO_ROOT/bin/resolveS" -a "$sam" -m 2 -d > "$stdout" 2> "$stderr"

    local actual_type
    local compatible_type
    actual_type="$(awk 'NR == 2 { print $2 }' "$stdout")"
    compatible_type="$(awk 'NR == 2 { print $3 }' "$stdout")"
    if [[ "$actual_type" != "$expected_type" ]]; then
        echo "FAIL $name: expected Strand_Type=$expected_type, got $actual_type" >&2
        echo "--- stdout ---" >&2
        cat "$stdout" >&2
        echo "--- stderr ---" >&2
        cat "$stderr" >&2
        return 1
    fi

    if [[ "$compatible_type" != "$expected_type" ]]; then
        echo "FAIL $name: expected Compatible_Strand_Type=$expected_type, got $compatible_type" >&2
        cat "$stdout" >&2
        return 1
    fi
}

run_case relative_diff_only_is_unstranded fr-unstranded \
    chr1:12:6 chr2:12:6 chr3:12:6

run_case both_metrics_support_secondstrand fr-secondstrand \
    chr1:20:0 chr2:20:0 chr3:20:0

run_case pvalue_only_is_unstranded fr-unstranded \
    chr1:550:450 chr2:550:450 chr3:550:450

echo "binomial strand detection tests passed"
