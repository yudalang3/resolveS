#!/bin/bash
# Regression test for auto_counting_withChrom.pl behavior boundaries that the
# single-pass MAPQ-tier refactor and the tie-breaker change are most sensitive to:
#   1. adaptive MAPQ descent + cumulative tier summing (MAPQ-20 -> MAPQ-10)
#   2. MAPQ=0 is always excluded, even at the loosest tier
#   3. pair-mode flag filtering (second-in-pair / not-proper-pair / mate-unmapped /
#      secondary / supplementary reverse reads must never be counted)
#   4. mode validation dies (single-on-paired, pair-on-single)
#   5. tie ordering is deterministic across Perl hash seeds (name tiebreaker)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PL="$REPO_ROOT/bin/auto_counting_withChrom.pl"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/resolveS_regression.XXXXXX")"

assert_eq() { # name expected actual
    if [[ "$3" != "$2" ]]; then
        printf 'FAIL [%s]\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
        exit 1
    fi
    echo "PASS [$1]"
}

assert_dies_with() { # name expected_substring sam mode
    local out="$TMP_DIR/die.out" err="$TMP_DIR/die.err"
    if perl "$PL" "$3" - lbl 0 "$4" > "$out" 2> "$err"; then
        echo "FAIL [$1]: command unexpectedly succeeded" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Fq "$2" "$err"; then
        echo "FAIL [$1]: stderr missing '$2'" >&2
        cat "$err" >&2
        exit 1
    fi
    echo "PASS [$1]"
}

TAB=$'\t'

# --- Case 1: adaptive MAPQ descent (MAPQ-20 all-insufficient -> MAPQ-10 success) ---
# 8 chroms: 2 reads at mapq 25 (tier0, total<18 => insufficient at MAPQ-20),
# plus 30 reads at mapq 15 (tier1) so the cumulative count at MAPQ-10 is 32 => 3of3.
ADAPT="$TMP_DIR/adaptive.sam"
perl -e '
for my $c (1..8) {
    print "a${c}_${_}\t67\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n" for 1..2;
    print "b${c}_${_}\t67\tchr${c}\t100\t15\t4M\t=\t200\t50\tACGT\tIIII\n" for 1..30;
}
' > "$ADAPT"
got="$(perl "$PL" "$ADAPT" - adaptive 0 pair)"
assert_eq "adaptive MAPQ descent" \
    "adaptive${TAB}fr-secondstrand${TAB}MAPQ-10${TAB}3of3${TAB}8${TAB}0${TAB}1${TAB}0${TAB}2" \
    "$got"

# --- Case 2: MAPQ=0 always excluded ---
# 4 chroms x 50 proper forward reads, all mapq 0 => nothing counted at any tier.
MAPQ0="$TMP_DIR/mapq0.sam"
perl -e '
for my $c (1..4) { print "z${c}_${_}\t67\tchr${c}\t100\t0\t4M\t=\t200\t50\tACGT\tIIII\n" for 1..50; }
' > "$MAPQ0"
got="$(perl "$PL" "$MAPQ0" - mapq0 0 pair)"
assert_eq "mapq=0 excluded" \
    "mapq0${TAB}insufficient-data${TAB}MAPQ-20${TAB}only-0-rRNAs-fallback${TAB}0${TAB}0${TAB}0${TAB}0${TAB}0" \
    "$got"

# Control: identical reads at mapq 20 ARE counted (proves the difference is the MAPQ).
MAPQ20="$TMP_DIR/mapq20.sam"
perl -e '
for my $c (1..4) { print "z${c}_${_}\t67\tchr${c}\t100\t20\t4M\t=\t200\t50\tACGT\tIIII\n" for 1..50; }
' > "$MAPQ20"
got="$(perl "$PL" "$MAPQ20" - mapq20 0 pair)"
assert_eq "mapq=20 control counted" \
    "mapq20${TAB}fr-secondstrand${TAB}MAPQ-20${TAB}3of3${TAB}4${TAB}0${TAB}1${TAB}0${TAB}2" \
    "$got"

# --- Case 3: pair-mode flag filtering ---
# 3 chroms x 20 good forward proper-pair R1 reads (mapq 25) => clean fr-secondstrand 3of3.
# Each chrom is also loaded with 50 REVERSE reads of every kind that must be dropped;
# if any leaked in, the chrom would flip to reverse-major and change the result.
FILTER="$TMP_DIR/pairfilter.sam"
perl -e '
for my $c (1..3) {
    print "g${c}_${_}\t67\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n" for 1..20;
    for my $i (1..50) {
        print "s${c}_${i}\t147\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n";  # second-in-pair, rev
        print "n${c}_${i}\t81\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n";   # not proper pair, rev
        print "m${c}_${i}\t91\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n";   # mate unmapped, rev
        print "e${c}_${i}\t323\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n";  # secondary, rev
        print "u${c}_${i}\t2115\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n"; # supplementary, rev
    }
}
' > "$FILTER"
got="$(perl "$PL" "$FILTER" - pairfilter 0 pair)"
assert_eq "pair flag filtering" \
    "pairfilter${TAB}fr-secondstrand${TAB}MAPQ-20${TAB}3of3${TAB}3${TAB}0${TAB}1${TAB}0${TAB}2" \
    "$got"

# --- Case 4: mode validation dies ---
PAIREDFLAG="$TMP_DIR/pairedflag.sam"
SINGLEFLAG="$TMP_DIR/singleflag.sam"
perl -e 'print "r${_}\t67\tchr1\t100\t25\t4M\t=\t200\t50\tA\tI\n" for 1..5' > "$PAIREDFLAG"
perl -e 'print "r${_}\t0\tchr1\t100\t25\t4M\t*\t0\t0\tA\tI\n" for 1..5'  > "$SINGLEFLAG"
assert_dies_with "single-mode on paired flags dies" \
    "paired-end records but single mode was selected" "$PAIREDFLAG" single
assert_dies_with "pair-mode on single flags dies" \
    "single-end records but pair mode was selected" "$SINGLEFLAG" pair

# --- Case 5: tie ordering is deterministic across hash seeds ---
# 5 chroms with identical totals (20 each) — a pure tie. With the name tiebreaker
# the -d debug table must be byte-identical regardless of PERL_HASH_SEED.
TIE="$TMP_DIR/tie.sam"
perl -e '
for my $c (1..5) { print "t${c}_${_}\t67\tchr${c}\t100\t25\t4M\t=\t200\t50\tACGT\tIIII\n" for 1..20; }
' > "$TIE"
PERL_HASH_SEED=1   perl "$PL" "$TIE" - tie 1 pair > /dev/null 2> "$TMP_DIR/tie.seed1.err"
PERL_HASH_SEED=999 perl "$PL" "$TIE" - tie 1 pair > /dev/null 2> "$TMP_DIR/tie.seed999.err"
if ! diff -q "$TMP_DIR/tie.seed1.err" "$TMP_DIR/tie.seed999.err" > /dev/null; then
    echo "FAIL [tie determinism]: debug table differs across hash seeds" >&2
    diff "$TMP_DIR/tie.seed1.err" "$TMP_DIR/tie.seed999.err" >&2 || true
    exit 1
fi
echo "PASS [tie determinism across hash seeds]"

# And the tied chroms are ordered by name (chr1..chr5).
order="$(grep -oE '^chr[0-9]+' "$TMP_DIR/tie.seed1.err" | tr '\n' ' ')"
assert_eq "tie name order" "chr1 chr2 chr3 chr4 chr5 " "$order"

echo "All MAPQ/adaptive regression tests passed"
echo "Temporary test files retained at: $TMP_DIR" >&2
