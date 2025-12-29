#!/bin/bash
# A script to count fragments from paired-end SAM file in 1M increments.
# For 8M read pairs, generates 8 records (1M, 2M, 3M, ... 8M).
# Counts only PRIMARY alignments that are PROPER PAIRS and MAPPED.
# Reports fragment strand based on R1's alignment direction.

# --- Input Handling ---
if [ -z "$1" ]; then
    echo "Usage: $0 <input_sam_file> <output_file> <index_str> [max_millions]"
    echo "  max_millions: Maximum number of millions to count (default: 8)"
    exit 1
fi

INPUT_FILE="$1"
INDEX_STR="$3"
MAX_MILLIONS="${4:-8}"  # Default to 8 million

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
awk -v max_m="$MAX_MILLIONS" -v idx_str="$INDEX_STR" '
BEGIN {
    total = 0;
    fwd = 0;
    rev = 0;
    unmapped = 0;
    not_proper = 0;
    sec = 0;
    supp = 0;
    r1_count = 0;
    current_million = 1;
}
!/^@/ {
    flag = $2
    total++

    # Only process R1 (first in pair, bit 0x40)
    if (int(flag / 64) % 2 != 1) {
        next
    }

    r1_count++

    # Check if unmapped (bit 0x4)
    if (int(flag / 4) % 2 == 1) {
        unmapped++
    }
    # Check if secondary (bit 0x100)
    else if (int(flag / 256) % 2 == 1) {
        sec++
    }
    # Check if supplementary (bit 0x800)
    else if (int(flag / 2048) % 2 == 1) {
        supp++
    }
    # Check if NOT proper pair (bit 0x2)
    else if (int(flag / 2) % 2 != 1) {
        not_proper++
    }
    # Count strand based on R1 direction (bit 0x10 = reverse)
    else if (int(flag / 16) % 2 == 1) {
        rev++
    }
    else {
        fwd++
    }

    # Output stats at each 1M R1 reads (fragments)
    if (r1_count == current_million * 1000000) {
        printf "%s %s %s %s %s %s %sM %s\n", r1_count, fwd, rev, unmapped, sec, supp, current_million, idx_str
        current_million++

        # Stop if we have processed max_millions
        if (current_million > max_m) {
            exit
        }
    }
}
END {
    # Output final stats if we did not reach a full million boundary
    if (r1_count > 0 && r1_count % 1000000 != 0 && current_million <= max_m) {
        printf "%s %s %s %s %s %s %sM_partial %s\n", r1_count, fwd, rev, unmapped, sec, supp, current_million, idx_str
    }
}' "$INPUT_FILE" >> "$OUTPUT_FILE"
