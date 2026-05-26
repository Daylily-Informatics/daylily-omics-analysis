#!/bin/bash
# fix_ont_cram_headers.sh
# Fixes @PG PP chain validation errors in ONT CRAM files by removing @PG lines
#
# The problem: ONT CRAM files have @PG lines with PP:basecaller references that
# sentieon driver validates but rejects when the referenced program doesn't exist.
#
# Usage:
#   Direct: ./fix_ont_cram_headers.sh <input_cram> [output_cram] [reference_fasta]
#   Slurm:  sbatch --comment RnD --partition i192,i192mem ./fix_ont_cram_headers.sh <input_cram> [output_cram] [reference_fasta]
#
# Defaults:
#   output_cram:    /fsx/scratch/downsamples/ont_cleaned/<basename>.cleaned.cram
#   reference_fasta: /fsx/references/genomic_data/hg38_crams/Homo_sapiens_assembly38.fasta
#
# Example:
#   sbatch --comment RnD --partition i192,i192mem ./fix_ont_cram_headers.sh \
#     /fsx/control_data/giab/HG003/ont/R0-HG003-D0-0-D0-PCR-FREE-ONT-PROMETHION.cram

set -euo pipefail

# Arguments with defaults
INPUT_CRAM="${1:-}"
DEFAULT_OUTDIR="/fsx/scratch/downsamples/ont_cleaned"
DEFAULT_REFERENCE="/fsx/references/genomic_data/hg38_crams/Homo_sapiens_assembly38.fasta"

if [[ -z "$INPUT_CRAM" ]]; then
    echo "Usage: $0 <input_cram> [output_cram] [reference_fasta]"
    echo ""
    echo "Defaults:"
    echo "  output_cram:    ${DEFAULT_OUTDIR}/<basename>.cleaned.cram"
    echo "  reference_fasta: ${DEFAULT_REFERENCE}"
    exit 1
fi

if [[ ! -f "$INPUT_CRAM" ]]; then
    echo "ERROR: Input CRAM not found: $INPUT_CRAM"
    exit 1
fi

CRAM_BASENAME=$(basename "$INPUT_CRAM" .cram)
OUTPUT_CRAM="${2:-${DEFAULT_OUTDIR}/${CRAM_BASENAME}.cleaned.cram}"
REFERENCE="${3:-${DEFAULT_REFERENCE}}"

if [[ ! -f "$REFERENCE" ]]; then
    echo "ERROR: Reference FASTA not found: $REFERENCE"
    exit 1
fi

# Create unique TMPDIR in /dev/shm
TMPDIR="/dev/shm/${CRAM_BASENAME}_fix_pg_$$"
export TMPDIR
export SENTIEON_TMPDIR="$TMPDIR"

# Trap for cleanup on any exit
cleanup() {
    echo "Cleaning up TMPDIR: $TMPDIR"
    rm -rf "$TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

# Create directories
mkdir -p "$TMPDIR"
mkdir -p "$(dirname "$OUTPUT_CRAM")"

echo "============================================"
echo "fix_ont_cram_headers.sh"
echo "============================================"
echo "Input:     $INPUT_CRAM"
echo "Output:    $OUTPUT_CRAM"
echo "Reference: $REFERENCE"
echo "TMPDIR:    $TMPDIR"
echo "Started:   $(date)"
echo "============================================"

# Create a clean header by filtering out @PG lines
echo "Extracting and filtering header..."
CLEAN_HEADER="$TMPDIR/clean_header.sam"
samtools view -H "$INPUT_CRAM" | grep -E '^@(HD|SQ|RG)' > "$CLEAN_HEADER"

echo "Header line counts:"
echo "  @HD: $(grep -c '^@HD' "$CLEAN_HEADER" || echo 0)"
echo "  @SQ: $(grep -c '^@SQ' "$CLEAN_HEADER" || echo 0)"
echo "  @RG: $(grep -c '^@RG' "$CLEAN_HEADER" || echo 0)"

# Re-encode CRAM with clean header
echo "Re-encoding CRAM with clean header..."
THREADS="${SLURM_CPUS_PER_TASK:-$(nproc)}"
echo "Using $THREADS threads"

samtools reheader -P "$CLEAN_HEADER" "$INPUT_CRAM" | \
    samtools view -@ "$THREADS" -T "$REFERENCE" -C -o "$OUTPUT_CRAM" -

echo "Creating index..."
samtools index -@ "$THREADS" "$OUTPUT_CRAM"

# Verify output
if [[ -f "$OUTPUT_CRAM" ]] && [[ -f "${OUTPUT_CRAM}.crai" ]]; then
    INPUT_SIZE=$(stat -c%s "$INPUT_CRAM" 2>/dev/null || stat -f%z "$INPUT_CRAM")
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_CRAM" 2>/dev/null || stat -f%z "$OUTPUT_CRAM")
    echo "Input size:  $INPUT_SIZE bytes"
    echo "Output size: $OUTPUT_SIZE bytes"
    
    PG_COUNT=$(samtools view -H "$OUTPUT_CRAM" | grep -c '^@PG' || echo 0)
    echo "Output @PG line count: $PG_COUNT"
    
    if [[ "$PG_COUNT" -eq 0 ]]; then
        echo "✅ SUCCESS: CRAM re-encoded with clean header (no @PG lines)"
    else
        echo "⚠️ WARNING: Output still has $PG_COUNT @PG lines"
    fi
else
    echo "❌ ERROR: Output file or index not created"
    exit 1
fi

echo "============================================"
echo "Completed: $(date)"
echo "============================================"

