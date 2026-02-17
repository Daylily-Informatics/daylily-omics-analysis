#!/bin/bash
# Fix missing ONT downsamples - regenerate 5x, 10x, 15x, 20x, 30x, 40x, 50x
# The original scripts used wrong source file (PAW81754 instead of PAY87954)

set -euo pipefail

# Correct source file
SOURCE_BAM="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
OUT_DIR="/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003"
JOBS_DIR="${OUT_DIR}/jobs"

# Coverage to fraction mapping (assuming ~60x base coverage)
# fraction = target_coverage / 60
declare -A FRACTIONS=(
    ["5x"]="0.083333"
    ["10x"]="0.166667"
    ["15x"]="0.250000"
    ["20x"]="0.333333"
    ["30x"]="0.500000"
    ["40x"]="0.666667"
    ["50x"]="0.833333"
)

mkdir -p "$JOBS_DIR"

# Clean up old tmp files
rm -f ${OUT_DIR}/tmp_*.bam ${OUT_DIR}/tmp_*.header.sam ${OUT_DIR}/tmp_*.fixed_header.sam 2>/dev/null || true

for cov in 5x 10x 15x 20x 30x 40x 50x; do
    FRAC="${FRACTIONS[$cov]}"
    OUT_CRAM="${OUT_DIR}/HG003_${cov}.cleaned.cram"
    
    # Skip if already exists
    if [ -f "$OUT_CRAM" ] && [ -s "$OUT_CRAM" ]; then
        echo "[$cov] Already exists: $(ls -lh $OUT_CRAM | awk '{print $5}')"
        continue
    fi
    
    cat > "${JOBS_DIR}/downsample_${cov}_fixed.sh" << EOF
#!/bin/bash
#SBATCH --job-name=ont_ds_${cov}
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=100G
#SBATCH --time=4:00:00
#SBATCH --output=${JOBS_DIR}/ont_ds_${cov}_fixed.%j.out
#SBATCH --error=${JOBS_DIR}/ont_ds_${cov}_fixed.%j.err

set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== Starting ${cov} downsample at \$(date) ==="
echo "Source: ${SOURCE_BAM}"
echo "Output: ${OUT_CRAM}"
echo "Fraction: ${FRAC}"

TMP_BAM="${OUT_DIR}/tmp_${cov}.bam"
TMP_HEADER="${OUT_DIR}/tmp_${cov}.header.sam"
FIXED_HEADER="${OUT_DIR}/tmp_${cov}.fixed_header.sam"

echo "[1/5] Downsampling..."
samtools view -@ 48 -s 33${FRAC} -b ${SOURCE_BAM} > \$TMP_BAM

echo "[2/5] Extracting header..."
samtools view -H \$TMP_BAM > \$TMP_HEADER

echo "[3/5] Fixing @PG headers (removing broken PP chain)..."
grep '^@HD\|^@SQ\|^@RG' \$TMP_HEADER > \$FIXED_HEADER
grep '^@PG' \$TMP_HEADER | sed 's/\tPP:[^\t]*//' >> \$FIXED_HEADER || true

echo "[4/5] Converting to CRAM with fixed header..."
samtools reheader \$FIXED_HEADER \$TMP_BAM | samtools view -@ 48 -C -T ${REF} -o ${OUT_CRAM}

echo "[5/5] Indexing..."
samtools index -@ 48 ${OUT_CRAM}

# Create .csi symlink if needed
if [ -f "${OUT_CRAM}.crai" ] && [ ! -f "${OUT_CRAM}.csi" ]; then
    ln -sf "${OUT_CRAM}.crai" "${OUT_CRAM}.csi"
fi

rm -f \$TMP_BAM \$TMP_HEADER \$FIXED_HEADER

echo "=== Complete: \$(ls -lh ${OUT_CRAM} | awk '{print \$5}') ==="
EOF

    chmod +x "${JOBS_DIR}/downsample_${cov}_fixed.sh"
    echo "[$cov] Submitting job..."
    sbatch "${JOBS_DIR}/downsample_${cov}_fixed.sh"
done

echo ""
echo "=== Jobs submitted ==="
squeue -u ubuntu | grep ont_ds || echo "No jobs in queue yet"

