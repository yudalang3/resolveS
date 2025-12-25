#!/bin/bash
# A script to count reads and classify alignments in a SAM file 
# based on their FLAG field.
# This script counts PRIMARY alignments only (excludes secondary/supplementary).

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
# Compatible with both mawk and gawk using modulo operations
# Filter reads with MAPQ > 20 for reliable alignments
awk '
BEGIN {
    total = 0;
    fwd = 0;
    rev = 0;
    unmapped = 0;
    sec = 0;
    supp = 0;
    low_mapq = 0;
}
!/^@/ {
    flag = $2
    mapq = $5
    total++
    
    # Check if bit 0x4 (unmapped) is set
    if (int(flag / 4) % 2 == 1) {
        unmapped++
        next
    }
    
    # Check if bit 0x100 (secondary) is set
    if (int(flag / 256) % 2 == 1) {
        sec++
        next
    }
    
    # Check if bit 0x800 (supplementary) is set
    if (int(flag / 2048) % 2 == 1) {
        supp++
        next
    }
    
    # Filter by MAPQ > 20 for reliable alignments
    if (mapq <= 20) {
        low_mapq++
        next
    }
    
    # Check if bit 0x10 (reverse strand) is set
    if (int(flag / 16) % 2 == 1)
        rev++
    else
        fwd++
}
END {
    printf "%s %s %s %s %s %s %s ", total, fwd, rev, unmapped, sec, supp, low_mapq
}' "$INPUT_FILE" >> "$OUTPUT_FILE"

echo $INDEX_STR >> "$OUTPUT_FILE"
