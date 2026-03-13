#!/bin/bash
echo "=== SACCT RECENT JOBS ==="
sacct -u ubuntu --format='JobID,JobName%50,State,ExitCode,Elapsed' -S 2026-02-17T22:00 2>/dev/null | tail -30

echo ""
echo "=== CLI ILMN Latest Log ==="
base=/fsx/analysis_results/ubuntu/t3-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis
log=$(ls -t $base/.snakemake/log/*.snakemake.log 2>/dev/null | head -1)
grep -E 'steps.*done|SUCCESS|Error|Finished job' "$log" 2>/dev/null | tail -10

echo ""
echo "=== CLI UG Latest Log ==="
base=/fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis
log=$(ls -t $base/.snakemake/log/*.snakemake.log 2>/dev/null | head -1)
grep -E 'steps.*done|SUCCESS|Error|Finished job' "$log" 2>/dev/null | tail -10

echo ""
echo "=== MOD ILMN Latest Log ==="
base=/fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis
log=$(ls -t $base/.snakemake/log/*.snakemake.log 2>/dev/null | head -1)
grep -E 'steps.*done|SUCCESS|Error|Finished job' "$log" 2>/dev/null | tail -10

echo ""
echo "=== RUNNING SNAKEMAKE ==="
ps aux | grep snakemake | grep -v grep | awk '{for(i=11;i<=NF;i++) printf "%s ",$i; print ""}'

