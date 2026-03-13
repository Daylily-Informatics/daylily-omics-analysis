#!/bin/bash
# Check what alignment targets exist

cd /fsx/analysis_results/ubuntu/test-pb-solo-3x/daylily-omics-analysis

echo "=== PacBio alignment targets ==="
source dyoainit 2>/dev/null
source bin/day_activate slurm hg38 2>/dev/null
bin/day_run --list 2>/dev/null | grep -iE "mm2|pacbio|pb" | head -10

echo ""
echo "=== Roche alignment targets ==="
bin/day_run --list 2>/dev/null | grep -iE "roche|sbx" | head -10

echo ""
echo "=== Check if Roche BAM is pre-aligned ==="
samtools view -H /fsx/data/genomic_data/organism_reads/H_sapiens/giab/roche/091025_webinar_data_giab_bam_bwa/HG003.bam 2>/dev/null | grep "^@SQ" | head -3

echo ""
echo "=== Check test-ug-solo-3x tmux ==="
tmux capture-pane -t test-ug-solo-3x -p 2>/dev/null | tail -10

