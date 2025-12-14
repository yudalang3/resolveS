#!/bin/bash

# Get the DIR of the SCRIPT
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOWTIE2_BIN="${SCRIPT_DIR}/../bowtie2/bowtie2"

# Check if input file is provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <input_file> <genome_index> [threads] [max_alig_reads]"
    echo "  input_file: Path to the input FASTQ file (required)"
    echo "  genome_index: Path to the genome index (required)"
    echo "  threads: Number of threads (optional, default: 6)"
    echo "  max_alig_reads: Maximum number of reads to align (optional, default: 4000000)"
    exit 1
fi
# Assign input parameters
INPUT_FILE="$1"
G_INDEX="$2"
THREADS="${3:-6}"  # Default to 6 if not provided
MAX_ALIG_READS="${4:-4000000}"  # Default to 4000000 if not provided

# Validate input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist."
    exit 1
fi

# Check if bowtie2 binary exists
if [ ! -f "$BOWTIE2_BIN" ]; then
    echo "Error: bowtie2 binary not found at $BOWTIE2_BIN"
    exit 1
fi


# Run bowtie2 alignment
"$BOWTIE2_BIN" -p "$THREADS" \
  -u "$MAX_ALIG_READS" \
  -x "$G_INDEX" \
  -U "$INPUT_FILE" \
  -S resolveS.sam
