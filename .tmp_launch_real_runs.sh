#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== Kill old sessions ==="
for s in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    tmux kill-session -t "$s" 2>/dev/null && echo "killed $s" || echo "$s already gone"
done

echo ""
echo "=== Launch REAL runs (no -n) ==="

declare -A TARGETS
TARGETS[test-sentdhipmr-3x]="produce_sentdhipmr_vcf produce_snv_concordances produce_alignstats"
TARGETS[test-sentdhuomr-3x]="produce_sentdhuomr_vcf produce_snv_concordances produce_alignstats"
TARGETS[test-sentdhupmr-3x]="produce_sentdhupmr_vcf produce_snv_concordances produce_alignstats"

for SESSION in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$SESSION/daylily-omics-analysis"
    tmux new-session -d -s "$SESSION"
    tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run ${TARGETS[$SESSION]} -p -k -j 20 -T 1 2>&1 | tee /tmp/${SESSION}_run.log" Enter
    echo "Launched REAL: $SESSION"
done

echo ""
echo "=== All 3 real runs launched ==="
echo "Monitor with: tmux ls"
echo "Check logs: tail -f /tmp/test-sent*_run.log"

