#!/bin/bash
# Remote check script - to be run ON the headnode
echo "=== CLI ILMN+ONT VCF ==="
ls -la /fsx/analysis_results/ubuntu/t3-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhio/vcfs/1-24/*.vcf.gz 2>/dev/null || echo "No VCF found"

echo ""
echo "=== CLI ILMN+ONT Snakemake Status ==="
tmux capture-pane -t t3-hybrid-cli-ilmn-ont-3x -p -S -200 2>/dev/null | grep -E 'SUCCESS|FAIL|Error|Exiting|steps.*done' | tail -5

echo ""
echo "=== CLI UG+ONT VCF ==="
ls -la /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/*.vcf.gz 2>/dev/null || echo "No VCF found"

echo ""
echo "=== CLI UG+ONT Snakemake Status ==="
tmux capture-pane -t t3-hybrid-cli-ug-ont-3x -p -S -200 2>/dev/null | grep -E 'SUCCESS|FAIL|Error|Exiting|steps.*done' | tail -5

echo ""
echo "=== SQUEUE ==="
squeue -u ubuntu --format='%.8i %.2t %.40j %.10M' 2>/dev/null | head -10

echo ""
echo "=== SNAKEMAKE PROCS ==="
ps aux | grep 'snakemake' | grep -v grep | wc -l

