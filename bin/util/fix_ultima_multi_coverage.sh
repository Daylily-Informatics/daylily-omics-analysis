#!/bin/bash
# Downsample Ultima CRAM to multiple coverage levels and fix headers (remove @PG lines)
# Usage: ./fix_ultima_multi_coverage.sh

set -euo pipefail

# Configuration - HG003 full-coverage Ultima CRAM (~99x)
INPUT_CRAM="/fsx/control_data/ug/Jan-2026-Sample-run/428437-L9353_L9354-Z0016-CATCCTGTGCGCATGAT.cram"
OUTPUT_BASE="/fsx/scratch/downsamples/ultima_cleaned_hg38_broad/HG003"
REFERENCE="/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
SEED=33
INPUT_COVERAGE=99.0  # Approximate input coverage

# Coverage levels to generate (skip 5x and 7x)
COVERAGES=(1 3 5 10 15 20 30 40 50)

# Create job directory
JOB_DIR="$OUTPUT_BASE/jobs"
mkdir -p "$JOB_DIR"

echo "=========================================="
echo "Ultima Downsampling + Header Fix"
echo "Input: $INPUT_CRAM"
echo "Input Coverage: ${INPUT_COVERAGE}x"
echo "Output base: $OUTPUT_BASE"
echo "Job scripts: $JOB_DIR"
echo "=========================================="

# Submit jobs for each coverage level
for COV in "${COVERAGES[@]}"; do
    # Calculate fraction and format for samtools -s SEED.FRAC
    # samtools expects FRAC as decimal without leading zero (e.g., 0.0101 -> .0101)
    FRACTION=$(awk "BEGIN {printf \"%.6f\", $COV / $INPUT_COVERAGE}" | sed 's/^0//')

    OUTPUT_CRAM="$OUTPUT_BASE/HG003_${COV}x.cleaned.cram"
    JOB_SCRIPT="$JOB_DIR/ug_ds_${COV}x.sh"

    echo "Creating job for ${COV}x (fraction: ${FRACTION})"
    echo "  Output: $OUTPUT_CRAM"

    cat > "$JOB_SCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=ug_ds_${COV}x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=180G
#SBATCH --time=6:00:00
#SBATCH --output=$JOB_DIR/ug_ds_${COV}x.%j.out
#SBATCH --error=$JOB_DIR/ug_ds_${COV}x.%j.err

set -euo pipefail

# Source conda environment for samtools
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== Starting ${COV}x Ultima downsample at \$(date) ==="
echo "Input: $INPUT_CRAM"
echo "Output: $OUTPUT_CRAM"
echo "Fraction: $FRACTION (seed: $SEED)"
echo "samtools version: \$(samtools --version | head -1)"

# Temp files
TMP_BAM="$OUTPUT_BASE/tmp_${COV}x.bam"
TMP_HEADER="$OUTPUT_BASE/tmp_${COV}x.header.sam"
FIXED_HEADER="$OUTPUT_BASE/tmp_${COV}x.fixed_header.sam"

# Step 1: Downsample
echo "[1/5] Downsampling to ${COV}x..."
samtools view -@ 64 -T "$REFERENCE" -b -s ${SEED}${FRACTION} "$INPUT_CRAM" > "\$TMP_BAM"
echo "Downsampled BAM size: \$(ls -lh \$TMP_BAM | awk '{print \$5}')"

# Step 2: Extract header and remove @PG lines
echo "[2/5] Extracting and fixing header..."
samtools view -H "\$TMP_BAM" > "\$TMP_HEADER"
grep -v "^@PG" "\$TMP_HEADER" > "\$FIXED_HEADER" || true
PG_COUNT=\$(grep -c "^@PG" "\$FIXED_HEADER" || echo 0)
echo "Remaining @PG lines: \$PG_COUNT"

# Step 3: Reheader and convert to CRAM
echo "[3/5] Reheading and converting to CRAM..."
samtools reheader "\$FIXED_HEADER" "\$TMP_BAM" | \\
    samtools view -@ 64 -C -T "$REFERENCE" -o "$OUTPUT_CRAM" -

# Step 4: Create index
echo "[4/5] Creating index..."
samtools index -@ 32 "$OUTPUT_CRAM"

# Step 5: Cleanup
echo "[5/5] Cleaning up temp files..."
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
echo "Outputs will be in: $OUTPUT_BASE"
echo "========================================"
