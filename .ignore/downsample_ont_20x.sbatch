#!/bin/bash
#SBATCH --job-name=ont-downsample-20x
#SBATCH --partition=i192,i128
#SBATCH --cpus-per-task=64
#SBATCH --time=720
#SBATCH --comment=daylily-global
#SBATCH --output=/fsx/scratch/ontbam/downsample_20x.slurm.log
#SBATCH --error=/fsx/scratch/ontbam/downsample_20x.slurm.err

set -euo pipefail

INPUT="/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam"
OUTDIR="/fsx/scratch/ontbam"
OUTPUT="${OUTDIR}/HG003_ONT_20x.sorted.bam"
THREADS=64

# PAY87954 is 31.17x mean coverage. 20/31.17 = 0.6416
FRACTION="42.6416"

echo "Starting downsample at $(date)"
echo "Input: ${INPUT}"
echo "Output: ${OUTPUT}"
echo "Fraction: ${FRACTION} (seed.frac)"
echo "Threads: ${THREADS}"

# Downsample, keep sorted (input is coordinate-sorted)
samtools view -@ ${THREADS} -b -s ${FRACTION} ${INPUT} \
  | samtools sort -@ ${THREADS} -m 2G -o ${OUTPUT} -

echo "Indexing at $(date)"
samtools index -@ ${THREADS} -c ${OUTPUT}

echo "Verifying at $(date)"
samtools quickcheck ${OUTPUT}

echo "Done at $(date)"
ls -lh ${OUTPUT} ${OUTPUT}.csi

