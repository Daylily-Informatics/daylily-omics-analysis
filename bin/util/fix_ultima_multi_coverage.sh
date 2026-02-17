#!/bin/bash
# Fix Ultima CRAM headers at multiple coverage levels (remove @PG lines)
# Usage: ./fix_ultima_multi_coverage.sh

set -euo pipefail

# Configuration
INPUT_BASE="/fsx/scratch/downsamples/ultima_reheadered/HG003/R0-HG003-D0-0-D0"
OUTPUT_BASE="/fsx/scratch/downsamples/ultima_reencoded/HG003/R0-HG003-D0-0-D0"
REFERENCE="/fsx/data/genomic_data/hg38_crams/Homo_sapiens_assembly38.fasta"

# Coverage levels to process (skip 5x and 7x)
# Use Np0x naming convention (e.g., 1p0x, 10p0x, 3p0x)
COVERAGES=("1p0" "3p0" "10p0" "15p0" "20p0" "30p0" "40p0" "50p0")

# Create job directory
JOB_DIR="$OUTPUT_BASE/jobs"
mkdir -p "$JOB_DIR"

echo "Output base: $OUTPUT_BASE"
echo "Job scripts: $JOB_DIR"

# Submit jobs for each coverage level
for COV in "${COVERAGES[@]}"; do
    INPUT_DIR="$INPUT_BASE/${COV}x"
    INPUT_CRAM="$INPUT_DIR/HG003_${COV}x.cram"
    OUTPUT_DIR="$OUTPUT_BASE/${COV}x"
    OUTPUT_CRAM="$OUTPUT_DIR/HG003_${COV}x.cram"
    JOB_SCRIPT="$JOB_DIR/fix_ug_${COV}x.sh"
    
    echo "Creating job for ${COV}x"
    echo "  Input:  $INPUT_CRAM"
    echo "  Output: $OUTPUT_CRAM"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Create a short name for slurm job (replace p0 with nothing for display)
    SHORT_COV="${COV//p0/}"

    cat > "$JOB_SCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=ug_fix_${SHORT_COV}x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=100G
#SBATCH --time=2:00:00
#SBATCH --output=$JOB_DIR/ug_fix_${COV}x.%j.out
#SBATCH --error=$JOB_DIR/ug_fix_${COV}x.%j.err

set -euo pipefail

# Source conda environment for samtools
source /fsx/data/cached_envs/mambaforge/etc/profile.d/conda.sh
conda activate SAM

echo "=== Starting ${COV}x Ultima header fix at \$(date) ==="
echo "Input: $INPUT_CRAM"
echo "Output: $OUTPUT_CRAM"
echo "samtools version: \$(samtools --version | head -1)"

# Check input exists
if [ ! -f "$INPUT_CRAM" ]; then
    echo "ERROR: Input file not found: $INPUT_CRAM"
    exit 1
fi

# Temp files
TMP_HEADER="$OUTPUT_DIR/tmp_${COV}x.header.sam"
FIXED_HEADER="$OUTPUT_DIR/tmp_${COV}x.fixed_header.sam"

# Step 1: Extract and fix header (remove all @PG lines)
echo "[1/4] Extracting and fixing header..."
samtools view -H "$INPUT_CRAM" > "\$TMP_HEADER"
grep -v "^@PG" "\$TMP_HEADER" > "\$FIXED_HEADER" || true

# Verify no @PG lines remain
PG_COUNT=\$(grep -c "^@PG" "\$FIXED_HEADER" || echo 0)
echo "Remaining @PG lines: \$PG_COUNT"

# Step 2: Reheader and re-encode as CRAM
echo "[2/4] Reheading and re-encoding CRAM..."
samtools reheader "\$FIXED_HEADER" "$INPUT_CRAM" | \
    samtools view -@ 64 -C -T "$REFERENCE" -o "$OUTPUT_CRAM" -

# Step 3: Create index
echo "[3/4] Creating index..."
samtools index -@ 32 "$OUTPUT_CRAM"

# Step 4: Cleanup temp files
echo "[4/4] Cleaning up..."
rm -f "\$TMP_HEADER" "\$FIXED_HEADER"

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

