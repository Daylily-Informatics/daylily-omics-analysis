#!/bin/bash
# Source conda directly, skip login shell noise
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate AUGMENT

BAM=/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam

echo "SAMTOOLS=$(which samtools)"
echo "VERSION=$(samtools --version 2>&1 | head -1)"

echo "=== HEADER (first 20 lines) ==="
samtools view -H "$BAM" 2>&1 | head -20

echo "=== FIRST 3 READS (cols 1-11) ==="
samtools view "$BAM" 2>&1 | head -3 | cut -f1-11

echo "=== READ COUNT + AVG LEN (first 1000) ==="
samtools view "$BAM" 2>&1 | head -1000 | awk '{sum+=length($10); n++} END{if(n>0) print "n="n, "avg_len="sum/n; else print "NO READS"}'

