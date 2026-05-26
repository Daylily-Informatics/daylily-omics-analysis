#!/bin/bash
# Merge two ONT BAMs and downsample to 30x and 40x target measured coverage
# PAY87954 (~26x) + PAY87794 (~31x) = ~57x combined
# Usage: bash merge_downsample_ont_combined.sh

set -euo pipefail

# Configuration
BAM1="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam"
BAM2="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87794.calls.sorted.bam"
REFERENCE="/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
OUTPUT_DIR="/fsx/scratch/downsamples/ont_merged_hg38_broad/HG003"
SCRATCH_DIR="/fsx/scratch/downsamples/ont_merged_hg38_broad/HG003"
SEED=33
COMBINED_COVERAGE=56.9  # ~26x + ~31x

# Target measured coverages
COVERAGES=(30 40)

# Create directories
mkdir -p "$SCRATCH_DIR/jobs"
echo "=========================================="
echo "ONT Merge + Downsample (PAY87954 + PAY87794)"
echo "Combined coverage: ~${COMBINED_COVERAGE}x"
echo "Scratch dir: $SCRATCH_DIR"
echo "Final output: $OUTPUT_DIR"
echo "=========================================="

for COV in "${COVERAGES[@]}"; do
    FRACTION=$(awk "BEGIN {printf \"%.6f\", $COV / $COMBINED_COVERAGE}" | sed 's/^0//')
    OUTPUT_CRAM="$OUTPUT_DIR/HG003_${COV}x_merged.cleaned.cram"
    JOB_SCRIPT="$SCRATCH_DIR/jobs/merge_ds_${COV}x.sh"

    echo "Creating job for ${COV}x (fraction: ${FRACTION})"
    echo "  Output: $OUTPUT_CRAM"

    cat > "$JOB_SCRIPT" << JOBEOF
#!/bin/bash
#SBATCH --job-name=ont_merge_ds_${COV}x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=da-us-west-2d-agbt-heavy
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=100G
#SBATCH --time=6:00:00
#SBATCH --output=$SCRATCH_DIR/jobs/merge_ds_${COV}x.%j.out
#SBATCH --error=$SCRATCH_DIR/jobs/merge_ds_${COV}x.%j.err

set -euo pipefail

source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== Starting ${COV}x merge+downsample at \$(date) ==="
echo "samtools version: \$(samtools --version | head -1)"
echo "BAM1: $BAM1"
echo "BAM2: $BAM2"
echo "Output: $OUTPUT_CRAM"
echo "Fraction: $FRACTION (seed: $SEED)"

TMP_DS1="$SCRATCH_DIR/tmp_87954_${COV}x.bam"
TMP_DS2="$SCRATCH_DIR/tmp_87794_${COV}x.bam"
TMP_MERGED="$SCRATCH_DIR/tmp_merged_${COV}x.bam"
TMP_HEADER="$SCRATCH_DIR/tmp_${COV}x.header.sam"
FIXED_HEADER="$SCRATCH_DIR/tmp_${COV}x.fixed_header.sam"

# Step 1: Downsample each BAM in parallel
echo "[1/6] Downsampling both BAMs in parallel..."
samtools view -@ 32 -b -s ${SEED}${FRACTION} "$BAM1" > "\$TMP_DS1" &
PID1=\$!
samtools view -@ 32 -b -s ${SEED}${FRACTION} "$BAM2" > "\$TMP_DS2" &
PID2=\$!
wait \$PID1 \$PID2
echo "DS1 size: \$(ls -lh \$TMP_DS1 | awk '{print \$5}')"
echo "DS2 size: \$(ls -lh \$TMP_DS2 | awk '{print \$5}')"

# Step 2: Concatenate downsampled BAMs
echo "[2/6] Concatenating downsampled BAMs..."
samtools cat -o "\$TMP_MERGED" "\$TMP_DS1" "\$TMP_DS2"
echo "Merged size: \$(ls -lh \$TMP_MERGED | awk '{print \$5}')"

# Step 3: Extract and fix header (remove @PG lines)
echo "[3/6] Extracting and fixing header..."
samtools view -H "\$TMP_MERGED" > "\$TMP_HEADER"
grep -v "^@PG" "\$TMP_HEADER" > "\$FIXED_HEADER" || true

# Step 4: Reheader and convert to CRAM
echo "[4/6] Reheading and converting to CRAM..."
samtools reheader "\$FIXED_HEADER" "\$TMP_MERGED" | \\
    samtools view -@ 32 -C -T "$REFERENCE" -o "$OUTPUT_CRAM" -

# Step 5: Index
echo "[5/6] Creating index..."
samtools index -@ 16 "$OUTPUT_CRAM"

# Step 6: Cleanup
echo "[6/6] Cleaning up temp files..."
rm -f "\$TMP_DS1" "\$TMP_DS2" "\$TMP_MERGED" "\$TMP_HEADER" "\$FIXED_HEADER"

echo ""
echo "=== Verification ==="
echo "CRAM size: \$(ls -lh $OUTPUT_CRAM | awk '{print \$5}')"
echo "Index: \$(ls -la ${OUTPUT_CRAM}.crai 2>/dev/null && echo YES || echo NO)"
echo "=== Completed ${COV}x at \$(date) ==="
JOBEOF

    chmod +x "$JOB_SCRIPT"
    echo ""
done

echo "=========================================="
echo "Job scripts created in: $SCRATCH_DIR/jobs/"
echo ""
echo "To submit:"
for COV in "${COVERAGES[@]}"; do
    echo "  sbatch $SCRATCH_DIR/jobs/merge_ds_${COV}x.sh"
done
echo ""
echo "Monitor: squeue -u \$USER"
echo "=========================================="

