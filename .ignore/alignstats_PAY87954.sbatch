#!/bin/bash
#SBATCH --job-name=alignstats-PAY87954
#SBATCH --partition=i192,i128
#SBATCH --cpus-per-task=64
#SBATCH --time=720
#SBATCH --output=/fsx/analysis_results/ubuntu/alignstats_giab_ont_hg003/alignstats_PAY87954.slurm.log
#SBATCH --error=/fsx/analysis_results/ubuntu/alignstats_giab_ont_hg003/alignstats_PAY87954.slurm.err

set -euo pipefail

ALIGNSTATS="/fsx/analysis_results/ubuntu/hiom-fresh-20260219-010532/daylily-omics-analysis/resources/alignstats/alignstats"
HUREF="/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta"
BAM="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam"
OUT_DIR="/fsx/analysis_results/ubuntu/alignstats_giab_ont_hg003"

echo "Starting alignstats PAY87954 at $(date)"
echo "Threads: 64"

${ALIGNSTATS} -C -U \
  -i ${BAM} \
  -T ${HUREF} \
  -o ${OUT_DIR}/PAY87954.alignstats.json \
  -j bam -v \
  -P 64 -p 64 \
  > ${OUT_DIR}/PAY87954.alignstats.log 2>&1

echo "Finished alignstats PAY87954 at $(date)"
echo "Output: ${OUT_DIR}/PAY87954.alignstats.json"

