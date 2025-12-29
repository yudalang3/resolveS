#!/bin/bash
# A script to count fragments from paired-end SAM file
# Counts only PRIMARY alignments that are PROPER PAIRS and MAPPED
# Reports fragment strand based on R1's alignment direction

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
# For paired-end data, we only count R1 reads to represent fragments
# Filters:
#   - Must be R1 (first in pair): FLAG & 0x40 (64)
#   - Must be proper pair: FLAG & 0x2 (2)
#   - Must be mapped: NOT (FLAG & 0x4)
#   - Must be primary: NOT (FLAG & 0x100) AND NOT (FLAG & 0x800)
# Strand is determined by R1's alignment direction (FLAG & 0x10)
awk '
BEGIN {
    total = 0;
    fwd = 0;
    rev = 0;
    unmapped = 0;
    not_proper = 0;
    sec = 0;
    supp = 0;
}
!/^@/ {
    flag = $2
    total++

    # Only process R1 (first in pair, bit 0x40)
    if (int(flag / 64) % 2 != 1) {
        next
    }

    # Check if unmapped (bit 0x4)
    if (int(flag / 4) % 2 == 1) {
        unmapped++
        next
    }

    # Check if secondary (bit 0x100)
    if (int(flag / 256) % 2 == 1) {
        sec++
        next
    }

    # Check if supplementary (bit 0x800)
    if (int(flag / 2048) % 2 == 1) {
        supp++
        next
    }

    # Check if proper pair (bit 0x2)
    if (int(flag / 2) % 2 != 1) {
        not_proper++
        next
    }

    # Count strand based on R1 direction (bit 0x10 = reverse)
    if (int(flag / 16) % 2 == 1)
        rev++
    else
        fwd++
}
END {
    # Output format matches fast version: total fwd rev unmapped sec supp not_proper
    printf "%s %s %s %s %s %s %s ", total, fwd, rev, unmapped, sec, supp, not_proper
}' "$INPUT_FILE" >> "$OUTPUT_FILE"

echo $INDEX_STR >> "$OUTPUT_FILE"
