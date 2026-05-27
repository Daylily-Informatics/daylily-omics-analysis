#!/bin/bash
#SBATCH --job-name=ont-ds15xact-clean
#SBATCH --partition=i192mem
#SBATCH --cpus-per-task=64
#SBATCH --mem=120G
#SBATCH --time=4:00:00
#SBATCH --output=/fsx/scratch/ontbam/downsample_15xactual.slurm.log
#SBATCH --error=/fsx/scratch/ontbam/downsample_15xactual.slurm.err

set -euo pipefail

. /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM

REF=/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta
INPUT=/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam
OUTPUT=/fsx/scratch/ontbam/HG003_15xactual.cleaned.cram
TEMPLATE=/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/HG003_10x.cleaned.cram
THREADS=64
FRACTION=42.4813

TMPDIR=$(mktemp -d /fsx/scratch/ontbam/tmp.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Starting downsample+clean at $(date)"
echo "Input: $INPUT"
echo "Output: $OUTPUT"
echo "Fraction: $FRACTION (seed=42, frac=0.4813 => 15x from 31.2x)"
echo "Reference: $REF"

# Build fixed header: @HD + @SQ from template (has M5/UR tags), @RG + @PG from source
samtools view -H "$TEMPLATE" | grep '^@HD\|^@SQ' > "$TMPDIR/fixed_header.sam"
samtools view -H "$INPUT" | grep '^@RG\|^@PG' >> "$TMPDIR/fixed_header.sam"

echo "Fixed header built ($(wc -l < "$TMPDIR/fixed_header.sam") lines)"

# Downsample and sort to temp BAM
echo "Downsampling and sorting..."
samtools view -@ "$THREADS" -b -s "$FRACTION" "$INPUT" | \
  samtools sort -@ "$THREADS" -m 2G -T "$TMPDIR/sort_tmp" -o "$TMPDIR/downsampled.bam" -

echo "Downsample+sort done at $(date)"

# Reheader and convert to CRAM
echo "Reheadering and converting to CRAM..."
samtools reheader "$TMPDIR/fixed_header.sam" "$TMPDIR/downsampled.bam" | \
  samtools view -@ "$THREADS" -C -T "$REF" -o "$OUTPUT" -

echo "CRAM conversion done at $(date)"

# Index
echo "Indexing..."
samtools index -@ "$THREADS" -c "$OUTPUT"

# Verify
samtools quickcheck "$OUTPUT"
echo "quickcheck passed"

echo "Done at $(date)"
ls -lh "$OUTPUT" "$OUTPUT.crai"

