#!/bin/bash

# Get the DIR of the SCRIPT
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOWTIE2_BIN="${SCRIPT_DIR}/../bowtie2/bowtie2"

# Check if input files are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <read.fq> <genome_index> [threads] [max_alig_reads] [output_sam]"
    echo "  read.fq: Path to the single-end FASTQ file (required)"
    echo "  genome_index: Path to the genome index (required)"
    echo "  threads: Number of threads (optional, default: 6)"
    echo "  max_alig_reads: Maximum number of reads to align (optional, default: 4000000)"
    echo "  output_sam: Output SAM path (optional, default: resolveS.sam)"
    exit 1
fi

# Assign input parameters
READ="$1"
G_INDEX="$2"
THREADS="${3:-6}"
MAX_ALIG_READS="${4:-4000000}"
OUTPUT_SAM="${5:-resolveS.sam}"

# Validate input file exists
if [ ! -f "$READ" ]; then
    echo "Error: FASTQ file '$READ' does not exist."
    exit 1
fi

# Check if bowtie2 binary exists
if [ ! -f "$BOWTIE2_BIN" ]; then
    echo "Error: bowtie2 binary not found at $BOWTIE2_BIN"
    exit 1
fi

# Run bowtie2 single-end alignment
# --no-sq: do not output @SQ headers
# --no-unal: suppress unaligned reads
"$BOWTIE2_BIN" -p "$THREADS" \
  -u "$MAX_ALIG_READS" --no-sq --no-unal \
  -x "$G_INDEX" \
  -U "$READ" \
  -S "$OUTPUT_SAM"
