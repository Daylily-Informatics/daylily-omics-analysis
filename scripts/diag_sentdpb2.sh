#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pacbio-solo-2/daylily-omics-analysis"
RESULTS_DIR="$ANALYSIS_DIR/results/day/hg38"

echo "=== 1. Check gvcf file sizes and validity ==="
for gvcf in $(find "$RESULTS_DIR" -path "*/snv/sentdpb/vcfs/*" -name "*.gvcf" -type f 2>/dev/null); do
    echo "--- $gvcf ---"
    ls -lh "$gvcf"
    # Check if it's a valid VCF (has header and data)
    head -1 "$gvcf" 2>/dev/null || echo "  EMPTY FILE"
    tail -3 "$gvcf" 2>/dev/null || echo "  CANNOT READ TAIL"
    wc -l "$gvcf" 2>/dev/null || echo "  CANNOT COUNT LINES"
done

echo ""
echo "=== 2. Check vcf output files (DNAModelApply output) ==="
for vcf in $(find "$RESULTS_DIR" -path "*/snv/sentdpb/vcfs/*" -name "*.vcf" -type f 2>/dev/null); do
    echo "--- $vcf ---"
    ls -lh "$vcf"
    head -1 "$vcf" 2>/dev/null || echo "  EMPTY FILE"
    wc -l "$vcf" 2>/dev/null || echo "  CANNOT COUNT LINES"
done

echo ""
echo "=== 3. Check gvcf.idx files ==="
find "$RESULTS_DIR" -path "*/snv/sentdpb/vcfs/*" -name "*.gvcf.idx" -type f -exec ls -lh {} \; 2>/dev/null || echo "No gvcf.idx files"

echo ""
echo "=== 4. Most recent snakemake log (last 80 lines) ==="
LATEST_SM_LOG=$(ls -t "$ANALYSIS_DIR/.snakemake/log/"*.snakemake.log 2>/dev/null | head -1)
if [ -n "$LATEST_SM_LOG" ]; then
    echo "File: $LATEST_SM_LOG"
    tail -80 "$LATEST_SM_LOG"
else
    echo "No snakemake logs found"
fi

echo ""
echo "=== 5. Second most recent snakemake log (last 80 lines) ==="
SECOND_SM_LOG=$(ls -t "$ANALYSIS_DIR/.snakemake/log/"*.snakemake.log 2>/dev/null | sed -n '2p')
if [ -n "$SECOND_SM_LOG" ]; then
    echo "File: $SECOND_SM_LOG"
    tail -80 "$SECOND_SM_LOG"
else
    echo "No second snakemake log found"
fi

echo ""
echo "=== 6. Check for HG003/HG004 sentdpb logs ==="
find "$RESULTS_DIR" -path "*HG003*sentdpb*" -name "*.log" -type f 2>/dev/null || echo "No HG003 sentdpb logs"
find "$RESULTS_DIR" -path "*HG004*sentdpb*" -name "*.log" -type f 2>/dev/null || echo "No HG004 sentdpb logs"

echo ""
echo "=== 7. Check dmesg for OOM kills ==="
dmesg 2>/dev/null | grep -i 'oom\|killed\|out of memory' | tail -10 || echo "No OOM messages (or no dmesg access)"

echo ""
echo "=== 8. Check slurm job status for recent sentdpb jobs ==="
sacct -S 2026-02-12 --format=JobID,JobName%40,State,ExitCode,MaxRSS,Elapsed,NodeList -n 2>/dev/null | grep -i "sentdpb\|sent_snv_pac" | tail -20 || echo "No sacct data or no matching jobs"

echo ""
echo "=== DONE ==="

