#!/bin/bash
# Quick fix: Create ONT 1x and 3x downsamples with correct source BAM
set -euo pipefail

# Configuration
INPUT_BAM="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam"
REFERENCE="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
OUTPUT_DIR="/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003"
SEED=33
INPUT_COVERAGE=60.0

# Ensure output dir exists
mkdir -p "$OUTPUT_DIR"

# Activate conda
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== ONT 1x and 3x Downsample Fix ==="
echo "Using source: $INPUT_BAM"

for COV in 1 3; do
    OUTPUT_CRAM="${OUTPUT_DIR}/HG003_${COV}x.cleaned.cram"
    
    # Skip if already exists
    if [ -f "$OUTPUT_CRAM" ] && [ -s "$OUTPUT_CRAM" ]; then
        echo "[$COV x] Already exists: $OUTPUT_CRAM"
        continue
    fi
    
    # Calculate fraction without leading zero
    FRACTION=$(awk "BEGIN {printf \"%.6f\", $COV / $INPUT_COVERAGE}" | sed 's/^0//')
    
    echo ""
    echo "[$COV x] Starting at $(date)"
    echo "[$COV x] Fraction: ${SEED}${FRACTION}"
    
    TMP_BAM="${OUTPUT_DIR}/tmp_fix_${COV}x.bam"
    TMP_HEADER="${OUTPUT_DIR}/tmp_fix_${COV}x.header"
    FIXED_HEADER="${OUTPUT_DIR}/tmp_fix_${COV}x.fixed_header"
    
    # Remove any stale files
    rm -f "$TMP_BAM" "$TMP_HEADER" "$FIXED_HEADER"
    
    # Downsample
    echo "[$COV x] Downsampling..."
    samtools view -@ 64 -b -s ${SEED}${FRACTION} "$INPUT_BAM" > "$TMP_BAM"
    
    # Extract and fix header
    echo "[$COV x] Fixing header..."
    samtools view -H "$TMP_BAM" > "$TMP_HEADER"
    grep -v "^@PG" "$TMP_HEADER" > "$FIXED_HEADER" || true
    
    # Convert to CRAM with fixed header
    echo "[$COV x] Converting to CRAM..."
    samtools reheader "$FIXED_HEADER" "$TMP_BAM" | samtools view -@ 64 -C -T "$REFERENCE" -o "$OUTPUT_CRAM" -
    
    # Index
    echo "[$COV x] Indexing..."
    samtools index -@ 32 "$OUTPUT_CRAM"
    
    # Cleanup
    rm -f "$TMP_BAM" "$TMP_HEADER" "$FIXED_HEADER"
    
    echo "[$COV x] Done: $(ls -lh "$OUTPUT_CRAM" | awk '{print $5}')"
done

echo ""
echo "=== Complete ==="
ls -lh "${OUTPUT_DIR}"/HG003_{1,3}x.cleaned.cram 2>/dev/null

