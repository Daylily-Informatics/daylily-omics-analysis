#!/bin/bash
# Downsample ONT BAM to multiple coverage levels and fix @PG headers
# Usage: ./downsample_ont_multi_coverage.sh

set -euo pipefail

# Configuration
INPUT_BAM="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAW81754.calls.sorted.bam"
REFERENCE="/fsx/data/genomic_data/hg38_crams/Homo_sapiens_assembly38.fasta"
OUTPUT_DIR="/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003"
SEED=33
INPUT_COVERAGE=60.0  # Assumed input coverage

# Coverage levels to generate (skip 7x per user request)
COVERAGES=(1 3 10 15 20 30 40 50)

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

# Create a temp directory for job scripts
JOB_DIR="$OUTPUT_DIR/jobs"
mkdir -p "$JOB_DIR"

# Submit jobs for each coverage level
for COV in "${COVERAGES[@]}"; do
    FRACTION=$(awk "BEGIN {printf \"%.4f\", $COV / $INPUT_COVERAGE}")
    OUTPUT_CRAM="$OUTPUT_DIR/HG003_${COV}x.cleaned.cram"
    JOB_SCRIPT="$JOB_DIR/downsample_${COV}x.sh"
    
    echo "Creating job for ${COV}x (fraction: $FRACTION)"
    
    cat > "$JOB_SCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=ont_ds_${COV}x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=100G
#SBATCH --time=4:00:00
#SBATCH --output=$JOB_DIR/ont_ds_${COV}x.%j.out
#SBATCH --error=$JOB_DIR/ont_ds_${COV}x.%j.err

set -euo pipefail

echo "=== Starting ${COV}x downsample at \$(date) ==="
echo "Input: $INPUT_BAM"
echo "Output: $OUTPUT_CRAM"
echo "Fraction: $FRACTION (seed: $SEED)"

# Temp files
TMP_BAM="$OUTPUT_DIR/tmp_${COV}x.bam"
TMP_HEADER="$OUTPUT_DIR/tmp_${COV}x.header.sam"
FIXED_HEADER="$OUTPUT_DIR/tmp_${COV}x.fixed_header.sam"

# Step 1: Downsample
echo "[1/5] Downsampling to ${COV}x..."
samtools view -@ 64 -b -s ${SEED}.${FRACTION} "$INPUT_BAM" > "\$TMP_BAM"
echo "Downsampled BAM size: \$(ls -lh \$TMP_BAM | awk '{print \$5}')"

# Step 2: Extract and fix header (remove all @PG lines)
echo "[2/5] Extracting and fixing header..."
samtools view -H "\$TMP_BAM" > "\$TMP_HEADER"
grep -v "^@PG" "\$TMP_HEADER" > "\$FIXED_HEADER" || true

# Verify no @PG lines remain
PG_COUNT=\$(grep -c "^@PG" "\$FIXED_HEADER" || echo 0)
echo "Remaining @PG lines: \$PG_COUNT"

# Step 3: Reheader and convert to CRAM
echo "[3/5] Reheading and converting to CRAM..."
samtools reheader "\$FIXED_HEADER" "\$TMP_BAM" | \
    samtools view -@ 32 -C -T "$REFERENCE" -o "$OUTPUT_CRAM" -

# Step 4: Create index
echo "[4/5] Creating index..."
samtools index -@ 16 "$OUTPUT_CRAM"

# Step 5: Cleanup temp files
echo "[5/5] Cleaning up..."
rm -f "\$TMP_BAM" "\$TMP_HEADER" "\$FIXED_HEADER"

# Verify output
echo ""
echo "=== Verification ==="
echo "CRAM size: \$(ls -lh $OUTPUT_CRAM | awk '{print \$5}')"
echo "Index exists: \$(ls -la ${OUTPUT_CRAM}.crai 2>/dev/null && echo 'YES' || echo 'NO')"
echo "@PG lines in output: \$(samtools view -H $OUTPUT_CRAM 2>/dev/null | grep -c '^@PG' || echo 0)"
echo ""
echo "=== Completed ${COV}x at \$(date) ==="
EOF

    chmod +x "$JOB_SCRIPT"
    
    # Submit the job
    sbatch "$JOB_SCRIPT"
    echo "Submitted job for ${COV}x"
    echo ""
done

echo "========================================"
echo "All jobs submitted! Monitor with: squeue -u \$USER"
echo "Outputs will be in: $OUTPUT_DIR"
echo "========================================"

