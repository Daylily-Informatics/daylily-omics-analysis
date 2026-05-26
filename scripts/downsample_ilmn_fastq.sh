#!/bin/bash
#SBATCH --job-name=ilmn_downsample
#SBATCH --partition=i192mem
#SBATCH --comment=daylily-global
#SBATCH --cpus-per-task=192
#SBATCH --mem=300G
#SBATCH --time=24:00:00
#SBATCH --output=/tmp/ilmn_downsample_%j.log

# Downsample Illumina FASTQ datasets for HG002 and HG003 at 40x and 50x coverage
# Submit with: sbatch /tmp/downsample_ilmn_fastq.sh

set -e

# Threads for seqkit
THREADS=192

# Activate conda environment
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate DAYOA

# Source FASTQs
HG002_R1="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/NA24385_R1.fastq.gz"
HG002_R2="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/NA24385_R2.fastq.gz"
HG003_R1="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/NA24149_R1.fastq.gz"
HG003_R2="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/NA24149_R2.fastq.gz"

# Coverage data from alignstats
HG002_COV=121.459813
HG003_COV=129.686776

# Random seed for reproducibility (same as other downsample operations)
SEED=42

# Output base directory (following pattern from other platforms)
OUT_BASE="/fsx/scratch/downsamples/ilmn"

# Calculate downsample fractions
# HG002: 40x = 40/121.459813 = 0.3293355, 50x = 50/121.459813 = 0.4116694
# HG003: 40x = 40/129.686776 = 0.3085073, 50x = 50/129.686776 = 0.3856342

echo "=== Illumina FASTQ Downsampling ==="
echo "HG002 source coverage: ${HG002_COV}x"
echo "HG003 source coverage: ${HG003_COV}x"
echo "Seed: ${SEED}"
echo ""

# Create output directories
for sample in HG002 HG003; do
    for cov in 40 50; do
        mkdir -p "${OUT_BASE}/${sample}/Ifull-${sample}-D1-1-D1/${cov}x"
    done
done

# Function to run seqkit sample
run_downsample() {
    local sample=$1
    local cov=$2
    local source_cov=$3
    local r1_in=$4
    local r2_in=$5
    
    local fraction=$(echo "scale=7; $cov / $source_cov" | bc)
    local out_dir="${OUT_BASE}/${sample}/Ifull-${sample}-D1-1-D1/${cov}x"
    local r1_out="${out_dir}/${sample}_${cov}x_R1.fastq.gz"
    local r2_out="${out_dir}/${sample}_${cov}x_R2.fastq.gz"
    
    echo "--- ${sample} ${cov}x (fraction: ${fraction}) ---"
    
    if [ -f "$r1_out" ] && [ -f "$r2_out" ]; then
        echo "Output files already exist, skipping..."
        return 0
    fi
    
    echo "R1: $(basename $r1_in) -> $(basename $r1_out)"
    seqkit sample -s $SEED -p $fraction -j $THREADS "$r1_in" -o "$r1_out"

    echo "R2: $(basename $r2_in) -> $(basename $r2_out)"
    seqkit sample -s $SEED -p $fraction -j $THREADS "$r2_in" -o "$r2_out"
    
    echo "Done: ${sample} ${cov}x"
    echo ""
}

echo "=== Starting downsampling ==="
echo ""

# HG002 40x
run_downsample "HG002" 40 $HG002_COV "$HG002_R1" "$HG002_R2"

# HG002 50x
run_downsample "HG002" 50 $HG002_COV "$HG002_R1" "$HG002_R2"

# HG003 40x
run_downsample "HG003" 40 $HG003_COV "$HG003_R1" "$HG003_R2"

# HG003 50x
run_downsample "HG003" 50 $HG003_COV "$HG003_R1" "$HG003_R2"

echo "=== Downsampling complete ==="
echo ""
echo "Output files:"
find "${OUT_BASE}" -name "*.fastq.gz" -type f -exec ls -lh {} \;

