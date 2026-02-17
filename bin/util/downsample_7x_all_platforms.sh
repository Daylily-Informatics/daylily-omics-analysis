#!/bin/bash
# Create 7x downsamples for ONT, Ultima, ILMN, and PacBio
# Usage: ./downsample_7x_all_platforms.sh

set -euo pipefail

# Common settings
SEED=33
REFERENCE="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
JOB_DIR="/fsx/scratch/downsamples/7x_jobs"
mkdir -p "$JOB_DIR"

echo "=========================================="
echo "Creating 7x downsamples for all platforms"
echo "=========================================="

# ============================================
# 1. ONT 7x (from 60x source)
# ============================================
ONT_INPUT="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAW81754.calls.sorted.bam"
ONT_OUTPUT_DIR="/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003"
ONT_OUTPUT="$ONT_OUTPUT_DIR/HG003_7x.cleaned.cram"
ONT_FRACTION=$(awk "BEGIN {printf \"%.6f\", 7 / 60}" | sed 's/^0//')

cat > "$JOB_DIR/ont_7x.sh" << EOF
#!/bin/bash
#SBATCH --job-name=ont_ds_7x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=100G
#SBATCH --time=4:00:00
#SBATCH --output=$JOB_DIR/ont_7x.%j.out
#SBATCH --error=$JOB_DIR/ont_7x.%j.err

set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== ONT 7x downsample at \$(date) ==="
TMP_BAM="$ONT_OUTPUT_DIR/tmp_7x.bam"
TMP_HEADER="$ONT_OUTPUT_DIR/tmp_7x.header.sam"
FIXED_HEADER="$ONT_OUTPUT_DIR/tmp_7x.fixed_header.sam"

samtools view -@ 64 -b -s ${SEED}${ONT_FRACTION} "$ONT_INPUT" > "\$TMP_BAM"
samtools view -H "\$TMP_BAM" > "\$TMP_HEADER"
grep -v "^@PG" "\$TMP_HEADER" > "\$FIXED_HEADER" || true
samtools reheader "\$FIXED_HEADER" "\$TMP_BAM" | samtools view -@ 64 -C -T "$REFERENCE" -o "$ONT_OUTPUT" -
samtools index -@ 32 "$ONT_OUTPUT"
rm -f "\$TMP_BAM" "\$TMP_HEADER" "\$FIXED_HEADER"
echo "Done: \$(ls -lh $ONT_OUTPUT)"
EOF
chmod +x "$JOB_DIR/ont_7x.sh"

# ============================================
# 2. Ultima 7x (from 99x source)
# ============================================
UG_INPUT="/fsx/data/ug/Jan-2026-Sample-run/428437-L9353_L9354-Z0016-CATCCTGTGCGCATGAT.cram"
UG_OUTPUT_DIR="/fsx/scratch/downsamples/ultima_cleaned_hg38_broad/HG003"
UG_OUTPUT="$UG_OUTPUT_DIR/HG003_7x.cleaned.cram"
UG_FRACTION=$(awk "BEGIN {printf \"%.6f\", 7 / 99}" | sed 's/^0//')

cat > "$JOB_DIR/ug_7x.sh" << EOF
#!/bin/bash
#SBATCH --job-name=ug_ds_7x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=96
#SBATCH --mem=180G
#SBATCH --time=6:00:00
#SBATCH --output=$JOB_DIR/ug_7x.%j.out
#SBATCH --error=$JOB_DIR/ug_7x.%j.err

set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== Ultima 7x downsample at \$(date) ==="
TMP_BAM="$UG_OUTPUT_DIR/tmp_7x.bam"
TMP_HEADER="$UG_OUTPUT_DIR/tmp_7x.header.sam"
FIXED_HEADER="$UG_OUTPUT_DIR/tmp_7x.fixed_header.sam"

samtools view -@ 64 -T "$REFERENCE" -b -s ${SEED}${UG_FRACTION} "$UG_INPUT" > "\$TMP_BAM"
samtools view -H "\$TMP_BAM" > "\$TMP_HEADER"
grep -v "^@PG" "\$TMP_HEADER" > "\$FIXED_HEADER" || true
samtools reheader "\$FIXED_HEADER" "\$TMP_BAM" | samtools view -@ 64 -C -T "$REFERENCE" -o "$UG_OUTPUT" -
samtools index -@ 32 "$UG_OUTPUT"
rm -f "\$TMP_BAM" "\$TMP_HEADER" "\$FIXED_HEADER"
echo "Done: \$(ls -lh $UG_OUTPUT)"
EOF
chmod +x "$JOB_DIR/ug_7x.sh"

# ============================================
# 3. ILMN 7x (from 20x fastq, fraction = 7/20 = 0.35)
# ============================================
ILMN_INPUT_R1="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_20x_R1.fastq.gz"
ILMN_INPUT_R2="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_20x_R2.fastq.gz"
ILMN_OUTPUT_DIR="/fsx/scratch/downsamples/ilmn/HG003/7x"
ILMN_FRACTION=$(awk "BEGIN {printf \"%.4f\", 7 / 20}")

cat > "$JOB_DIR/ilmn_7x.sh" << EOF
#!/bin/bash
#SBATCH --job-name=ilmn_ds_7x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=2:00:00
#SBATCH --output=$JOB_DIR/ilmn_7x.%j.out
#SBATCH --error=$JOB_DIR/ilmn_7x.%j.err

set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== ILMN 7x downsample at \$(date) ==="
mkdir -p "$ILMN_OUTPUT_DIR"

# Use seqtk for fastq downsampling (same seed for both R1 and R2)
seqtk sample -s $SEED "$ILMN_INPUT_R1" $ILMN_FRACTION | gzip > "$ILMN_OUTPUT_DIR/HG003_7x_R1.fastq.gz"
seqtk sample -s $SEED "$ILMN_INPUT_R2" $ILMN_FRACTION | gzip > "$ILMN_OUTPUT_DIR/HG003_7x_R2.fastq.gz"

echo "Done:"
ls -lh "$ILMN_OUTPUT_DIR/"
EOF
chmod +x "$JOB_DIR/ilmn_7x.sh"

# ============================================
# 4. PacBio 7x (from 10x bam, fraction = 7/10 = 0.7)
# ============================================
PB_INPUT="/fsx/scratch/downsamples/pacbio/HG003/R0-HG003-D0-0-D0/10p0x/HG003_10p0x.bam"
PB_OUTPUT_DIR="/fsx/scratch/downsamples/pacbio/HG003/R0-HG003-D0-0-D0/7p0x"
PB_OUTPUT="$PB_OUTPUT_DIR/HG003_7p0x.bam"
PB_FRACTION=$(awk "BEGIN {printf \"%.6f\", 7 / 10}" | sed 's/^0//')

cat > "$JOB_DIR/pb_7x.sh" << EOF
#!/bin/bash
#SBATCH --job-name=pb_ds_7x
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --comment=RnD
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=2:00:00
#SBATCH --output=$JOB_DIR/pb_7x.%j.out
#SBATCH --error=$JOB_DIR/pb_7x.%j.err

set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

echo "=== PacBio 7x downsample at \$(date) ==="
mkdir -p "$PB_OUTPUT_DIR"

samtools view -@ 32 -b -s ${SEED}${PB_FRACTION} "$PB_INPUT" > "$PB_OUTPUT"
samtools index -@ 16 "$PB_OUTPUT"

echo "Done:"
ls -lh "$PB_OUTPUT_DIR/"
EOF
chmod +x "$JOB_DIR/pb_7x.sh"

# Submit all jobs
echo ""
echo "Submitting jobs..."
sbatch "$JOB_DIR/ont_7x.sh"
sbatch "$JOB_DIR/ug_7x.sh"
sbatch "$JOB_DIR/ilmn_7x.sh"
sbatch "$JOB_DIR/pb_7x.sh"

echo ""
echo "=========================================="
echo "All 7x downsample jobs submitted!"
echo "Monitor with: squeue -u \$USER"
echo "=========================================="

