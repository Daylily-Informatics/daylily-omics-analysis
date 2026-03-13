#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pacbio-solo-2/daylily-omics-analysis"
RESULTS_DIR="$ANALYSIS_DIR/results/day/hg38"

echo "=== 1. List samples in results dir ==="
ls -d "$RESULTS_DIR"/*/ 2>/dev/null | head -20 || echo "No sample dirs found"

echo ""
echo "=== 2. Find sentdpb log files (most recent first) ==="
find "$RESULTS_DIR" -path "*/snv/sentdpb/log/vcfs/*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -20 || echo "No sentdpb logs found"

echo ""
echo "=== 3. Find sentdpb gvcf/vcf output files ==="
find "$RESULTS_DIR" -path "*/snv/sentdpb/vcfs/*" -name "*.gvcf" -type f -printf '%s %T@ %p\n' 2>/dev/null | sort -rn | head -20 || echo "No gvcf files found"
find "$RESULTS_DIR" -path "*/snv/sentdpb/vcfs/*" -name "*.vcf" -type f -printf '%s %T@ %p\n' 2>/dev/null | sort -rn | head -20 || echo "No vcf files found"

echo ""
echo "=== 4. Check snakemake logs ==="
ls -lt "$ANALYSIS_DIR/.snakemake/log/" 2>/dev/null | head -5 || echo "No snakemake logs"

echo ""
echo "=== 5. Check LD_LIBRARY_PATH ==="
echo "Current LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-<unset>}"

echo ""
echo "=== 6. Check libstdc++ in conda envs ==="
find /fsx/resources/environments/conda -name "libstdc++.so.6" -type l 2>/dev/null | while read f; do
    target=$(readlink -f "$f")
    max_glibcxx=$(strings "$f" | grep "^GLIBCXX_3\.4\." | sort -t. -k3 -n | tail -1)
    echo "$f -> $target  (max: $max_glibcxx)"
done

echo ""
echo "=== DONE ==="

