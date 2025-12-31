#!/bin/bash
# A script to count chromosomes from paired-end SAM file
# Each chromosome counts as ONE, strand determined by MAJOR (majority) strand
# Output format: total fwd rev unmapped sec supp not_proper

# --- Input Handling ---
if [ -z "$1" ]; then
    echo "Usage: $0 <input_sam_file> <output_file> <index_str>"
    exit 1
fi

INPUT_FILE="$1"
INDEX_STR="$3"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

if [ -n "$2" ]; then
    OUTPUT_FILE="$2"
else
    if [[ "$INPUT_FILE" == *.sam ]]; then
        OUTPUT_FILE="${INPUT_FILE%.sam}.counts.txt"
    else
        OUTPUT_FILE="${INPUT_FILE}.counts.txt"
    fi
fi

# --- Awk Command Execution ---
# For each chromosome, count all valid alignments first
# Then determine strand by majority vote
awk '
!/^@/ {
    flag = $2
    chrom = $3
    mapq = $5

    # Must be paired (bit 0x1)
    if (int(flag / 1) % 2 != 1) next

    # Only process R1 (first in pair, bit 0x40)
    if (int(flag / 64) % 2 != 1) next

    # Check if unmapped (bit 0x4)
    if (int(flag / 4) % 2 == 1) {
        unmapped_chrom[chrom] = 1
        next
    }

    # Check if mate unmapped (bit 0x8)
    if (int(flag / 8) % 2 == 1) {
        unmapped_chrom[chrom] = 1
        next
    }

    # Check if secondary (bit 0x100)
    if (int(flag / 256) % 2 == 1) {
        sec_chrom[chrom] = 1
        next
    }

    # Check if supplementary (bit 0x800)
    if (int(flag / 2048) % 2 == 1) {
        supp_chrom[chrom] = 1
        next
    }

    # Check MAPQ >= 4
    if (mapq < 4) {
        not_proper_chrom[chrom] = 1
        next
    }

    # Check if proper pair (bit 0x2)
    if (int(flag / 2) % 2 != 1) {
        not_proper_chrom[chrom] = 1
        next
    }

    # Valid alignment - count strand per chromosome
    valid_chrom[chrom] = 1
    if (int(flag / 16) % 2 == 1)
        rev_count[chrom]++
    else
        fwd_count[chrom]++
}
END {
    total = 0
    fwd = 0
    rev = 0
    unmapped = 0
    sec = 0
    supp = 0
    not_proper = 0

    # Count valid chromosomes by major strand
    for (c in valid_chrom) {
        total++
        f = (c in fwd_count) ? fwd_count[c] : 0
        r = (c in rev_count) ? rev_count[c] : 0
        if (f >= r)
            fwd++
        else
            rev++
    }

    # Count chromosomes that only have unmapped/sec/supp/not_proper
    for (c in unmapped_chrom) {
        if (!(c in valid_chrom)) {
            total++
            unmapped++
        }
    }
    for (c in sec_chrom) {
        if (!(c in valid_chrom) && !(c in unmapped_chrom)) {
            total++
            sec++
        }
    }
    for (c in supp_chrom) {
        if (!(c in valid_chrom) && !(c in unmapped_chrom) && !(c in sec_chrom)) {
            total++
            supp++
        }
    }
    for (c in not_proper_chrom) {
        if (!(c in valid_chrom) && !(c in unmapped_chrom) && !(c in sec_chrom) && !(c in supp_chrom)) {
            total++
            not_proper++
        }
    }

    printf "%s %s %s %s %s %s %s ", total, fwd, rev, unmapped, sec, supp, not_proper
}' "$INPUT_FILE" >> "$OUTPUT_FILE"

echo $INDEX_STR >> "$OUTPUT_FILE"
