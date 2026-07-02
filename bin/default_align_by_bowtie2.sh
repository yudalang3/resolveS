#!/bin/bash

# Get the DIR of the SCRIPT
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOWTIE2_BIN="${SCRIPT_DIR}/../bowtie2/bowtie2"

# Check if input files are provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 <read1.fq> <read2.fq> <genome_index> [threads] [max_alig_reads] [output_sam]"
    echo "  read1.fq: Path to the R1 FASTQ file (required)"
    echo "  read2.fq: Path to the R2 FASTQ file (required)"
    echo "  genome_index: Path to the genome index (required)"
    echo "  threads: Number of threads (optional, default: 6)"
    echo "  max_alig_reads: Maximum number of read pairs to align (optional, default: 4000000)"
    echo "  output_sam: Output SAM path (optional, default: resolveS.sam)"
    exit 1
fi

# Assign input parameters
READ1="$1"
READ2="$2"
G_INDEX="$3"
THREADS="${4:-6}"
MAX_ALIG_READS="${5:-4000000}"
OUTPUT_SAM="${6:-resolveS.sam}"

# Validate input files exist
if [ ! -f "$READ1" ]; then
    echo "Error: R1 file '$READ1' does not exist."
    exit 1
fi

if [ ! -f "$READ2" ]; then
    echo "Error: R2 file '$READ2' does not exist."
    exit 1
fi

# Check if bowtie2 binary exists
if [ ! -f "$BOWTIE2_BIN" ]; then
    echo "Error: bowtie2 binary not found at $BOWTIE2_BIN"
    exit 1
fi

# Run bowtie2 paired-end alignment
# --no-sq: do not output @SQ headers
# --no-unal: suppress unaligned reads
# --no-mixed: suppress unpaired alignments for paired reads
# --no-discordant: suppress discordant alignments for paired reads
# This ensures only concordant pairs (both mates mapped correctly) are output
"$BOWTIE2_BIN" -p "$THREADS" \
  -u "$MAX_ALIG_READS" --no-sq --no-unal \
  --no-mixed --no-discordant \
  -x "$G_INDEX" \
  -1 "$READ1" \
  -2 "$READ2" \
  -S "$OUTPUT_SAM"
