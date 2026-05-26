#!/bin/bash
# downsample_cram_batch.sh
# Downsamples a CRAM file to target coverage(s) using samtools
#
# Usage:
#   Direct: ./downsample_cram_batch.sh <input_cram> <input_coverage> <target_coverages> [output_dir] [reference_fasta] [seed]
#   Slurm:  sbatch --comment RnD --partition i192,i192mem ./downsample_cram_batch.sh <input_cram> <input_coverage> <target_coverages>
#
# Arguments:
#   input_cram:       Path to input CRAM file
#   input_coverage:   Current coverage of input (e.g., 30)
#   target_coverages: Comma-separated target coverages (e.g., "5,10,15" or "5")
#
# Defaults:
#   output_dir:       /fsx/scratch/downsamples/<platform>_cleaned/
#   reference_fasta:  /fsx/references/genomic_data/hg38_crams/Homo_sapiens_assembly38.fasta
#   seed:             42
#
# Example:
#   sbatch --comment RnD --partition i192,i192mem ./downsample_cram_batch.sh \
#     /fsx/control_data/giab/HG003/ilmn/HG003_30x.cram 30 "5,10,15"

set -euo pipefail

# Arguments
INPUT_CRAM="${1:-}"
INPUT_COV="${2:-}"
TARGET_COVS="${3:-}"
DEFAULT_REFERENCE="/fsx/references/genomic_data/hg38_crams/Homo_sapiens_assembly38.fasta"
SEED="${6:-42}"

if [[ -z "$INPUT_CRAM" ]] || [[ -z "$INPUT_COV" ]] || [[ -z "$TARGET_COVS" ]]; then
    echo "Usage: $0 <input_cram> <input_coverage> <target_coverages> [output_dir] [reference_fasta] [seed]"
    echo ""
    echo "Arguments:"
    echo "  input_cram:       Path to input CRAM file"
    echo "  input_coverage:   Current coverage of input (e.g., 30)"
    echo "  target_coverages: Comma-separated target coverages (e.g., '5,10,15')"
    echo ""
    echo "Example:"
    echo "  $0 /fsx/control_data/HG003.cram 30 '5,10,15'"
    exit 1
fi

if [[ ! -f "$INPUT_CRAM" ]]; then
    echo "ERROR: Input CRAM not found: $INPUT_CRAM"
    exit 1
fi

# Detect platform from filename or path
CRAM_BASENAME=$(basename "$INPUT_CRAM" .cram)
if [[ "$INPUT_CRAM" == *"ont"* ]] || [[ "$INPUT_CRAM" == *"ONT"* ]]; then
    PLATFORM="ont"
elif [[ "$INPUT_CRAM" == *"pacbio"* ]] || [[ "$INPUT_CRAM" == *"PACBIO"* ]] || [[ "$INPUT_CRAM" == *"pb"* ]]; then
    PLATFORM="pacbio"
elif [[ "$INPUT_CRAM" == *"ultima"* ]] || [[ "$INPUT_CRAM" == *"ULTIMA"* ]] || [[ "$INPUT_CRAM" == *"UG"* ]]; then
    PLATFORM="ultima"
else
    PLATFORM="ilmn"
fi

DEFAULT_OUTDIR="/fsx/scratch/downsamples/${PLATFORM}_cleaned"
OUTPUT_DIR="${4:-${DEFAULT_OUTDIR}}"
REFERENCE="${5:-${DEFAULT_REFERENCE}}"

if [[ ! -f "$REFERENCE" ]]; then
    echo "ERROR: Reference FASTA not found: $REFERENCE"
    exit 1
fi

# Create unique TMPDIR in /dev/shm
TMPDIR="/dev/shm/${CRAM_BASENAME}_ds_$$"
export TMPDIR

# Trap for cleanup on any exit
cleanup() {
    echo "Cleaning up TMPDIR: $TMPDIR"
    rm -rf "$TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

# Create directories
mkdir -p "$TMPDIR"
mkdir -p "$OUTPUT_DIR"

THREADS="${SLURM_CPUS_PER_TASK:-$(nproc)}"

echo "============================================"
echo "downsample_cram_batch.sh"
echo "============================================"
echo "Input:      $INPUT_CRAM"
echo "Input Cov:  ${INPUT_COV}x"
echo "Targets:    $TARGET_COVS"
echo "Output Dir: $OUTPUT_DIR"
echo "Reference:  $REFERENCE"
echo "Platform:   $PLATFORM"
echo "Seed:       $SEED"
echo "Threads:    $THREADS"
echo "TMPDIR:     $TMPDIR"
echo "Started:    $(date)"
echo "============================================"

# Process each target coverage
IFS=',' read -ra TARGETS <<< "$TARGET_COVS"
for TGT in "${TARGETS[@]}"; do
    TGT=$(echo "$TGT" | tr -d ' ')  # Remove whitespace
    
    if (( $(echo "$TGT >= $INPUT_COV" | bc -l) )); then
        echo "⚠️ Skipping ${TGT}x (>= input ${INPUT_COV}x)"
        continue
    fi
    
    FRACTION=$(echo "scale=10; $TGT / $INPUT_COV" | bc)
    SUBSAMPLE_ARG="${SEED}.${FRACTION#0.}"  # Format: SEED.FRACTION (e.g., 42.16667)
    
    OUTPUT_CRAM="${OUTPUT_DIR}/${CRAM_BASENAME}_${TGT}x.cram"
    
    echo ""
    echo ">>> Downsampling to ${TGT}x (fraction: $FRACTION)..."
    echo "    Output: $OUTPUT_CRAM"
    
    samtools view -@ "$THREADS" -s "$SUBSAMPLE_ARG" -C -T "$REFERENCE" \
        -o "$OUTPUT_CRAM" "$INPUT_CRAM"
    
    echo "    Indexing..."
    samtools index -@ "$THREADS" "$OUTPUT_CRAM"
    
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_CRAM" 2>/dev/null || stat -f%z "$OUTPUT_CRAM")
    echo "    ✅ Created: $OUTPUT_CRAM ($OUTPUT_SIZE bytes)"
done

echo ""
echo "============================================"
echo "Completed: $(date)"
echo "============================================"

