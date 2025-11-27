#!/bin/bash

# Check if input file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_file> [threads]"
    echo "  input_file: Path to the input FASTQ file (required)"
    echo "  threads: Number of threads (optional, default: 6)"
    exit 1
fi

# Assign input parameters
INPUT_FILE="$1"
THREADS="${2:-6}"  # Default to 6 if not provided

# Validate input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist."
    exit 1
fi

# Check if bowtie2 is available
if ! command -v bowtie2 &> /dev/null; then
    echo "Error: bowtie2 is not installed or not in PATH."
    exit 1
fi


# Run bowtie2 alignment
bowtie2 -p "$THREADS" \
  -u 4000000 \
  -x /home/dell/projects/estimate_strand4NGS/ref_bowtie2/default \
  -U "$INPUT_FILE" \
  -S resolveS.sam 2> log_bowtie2_stats.txt
