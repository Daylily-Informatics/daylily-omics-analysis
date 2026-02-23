#!/bin/bash
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate AUGMENT

echo "=== Source CRAM file sizes ==="
CRAM_DIR=/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont
ls -lh "$CRAM_DIR"/HG003_*.cleaned.cram 2>/dev/null

echo ""
echo "=== Full BAM file size ==="
ls -lh /fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam

echo ""
echo "=== Byte sizes for ratio calc ==="
for f in "$CRAM_DIR"/HG003_*.cleaned.cram; do
    sz=$(stat --format=%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
    echo "$(basename $f) $sz"
done
BAM=/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam
sz=$(stat --format=%s "$BAM" 2>/dev/null || stat -f%z "$BAM" 2>/dev/null)
echo "PAY87954.calls.sorted.bam $sz"

echo ""
echo "=== Also check if there are other files in the giab_2025.01 dir ==="
ls -lh /fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/

