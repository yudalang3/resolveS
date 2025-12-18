#!/bin/bash
# A script to count reads and classify alignments in a SAM file
# in 1M increments. For 8M reads, generates 8 records (1M, 2M, 3M, ... 8M).

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
# Process SAM file and output counts at each 1M increment
# Compatible with both mawk and gawk using modulo operations
awk -v max_m="$MAX_MILLIONS" -v idx_str="$INDEX_STR" '
BEGIN {
    total = 0;
    fwd = 0;
    rev = 0;
    unmapped = 0;
    sec = 0;
    supp = 0;
    current_million = 1;
    reads_in_current_batch = 0;
}
!/^@/ {
    flag = $2
    total++
    reads_in_current_batch++
    
    # Check if bit 0x4 (unmapped) is set
    if (int(flag / 4) % 2 == 1) {
        unmapped++
    }
    # Check if bit 0x100 (secondary) is set
    else if (int(flag / 256) % 2 == 1) {
        sec++
    }
    # Check if bit 0x800 (supplementary) is set
    else if (int(flag / 2048) % 2 == 1) {
        supp++
    }
    # Check if bit 0x10 (reverse strand) is set
    else if (int(flag / 16) % 2 == 1) {
        rev++
    }
    else {
        fwd++
    }
    
    # Output stats at each 1M reads
    if (total == current_million * 1000000) {
        printf "%s %s %s %s %s %s %sM %s\n", total, fwd, rev, unmapped, sec, supp, current_million, idx_str
        current_million++
        
        # Stop if we have processed max_millions
        if (current_million > max_m) {
            exit
        }
    }
}
END {
    # Output final stats if we did not reach a full million boundary
    if (total > 0 && total % 1000000 != 0 && current_million <= max_m) {
        printf "%s %s %s %s %s %s %sM_partial %s\n", total, fwd, rev, unmapped, sec, supp, current_million, idx_str
    }
}' "$INPUT_FILE" >> "$OUTPUT_FILE"
