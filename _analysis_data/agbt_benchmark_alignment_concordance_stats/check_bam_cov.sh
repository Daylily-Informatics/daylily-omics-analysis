#!/bin/bash
BAM=/fsx/data/genomic_data/organism_reads/H_sapiens/giab/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam
GENOME_SIZE=3088286401

echo "=== BAM file size ==="
ls -lh "$BAM"

echo ""
echo "=== Header: SQ lines (chromosomes) ==="
samtools view -H "$BAM" 2>/dev/null | grep -c @SQ

echo ""
echo "=== Read groups ==="
samtools view -H "$BAM" 2>/dev/null | grep @RG

echo ""
echo "=== Sampling first 1000 reads for avg length ==="
samtools view "$BAM" 2>/dev/null | head -1000 | awk '{sum+=length($10); n++} END{print "sampled_reads="n, "avg_read_len="sum/n}'

echo ""
echo "=== Coverage estimate from first 1000 reads + total read count ==="
echo "(Running samtools view -c ... this may take a few minutes on 103GB)"
TOTAL=$(samtools view -c "$BAM" 2>/dev/null)
AVG_LEN=$(samtools view "$BAM" 2>/dev/null | head -1000 | awk '{sum+=length($10); n++} END{print sum/n}')
echo "total_reads=$TOTAL"
echo "avg_read_len=$AVG_LEN"
echo "genome_size=$GENOME_SIZE"
COV=$(echo "$TOTAL * $AVG_LEN / $GENOME_SIZE" | bc -l 2>/dev/null || python3 -c "print(f'{$TOTAL * $AVG_LEN / $GENOME_SIZE:.2f}')")
echo "estimated_coverage=${COV}x"

