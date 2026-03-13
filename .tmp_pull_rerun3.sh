#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== Pull ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    cd "$BASE/$d/daylily-omics-analysis"
    git pull origin feat/modular-hybrid-workflows 2>&1 | tail -2
    echo "$d: $(git log --oneline -1)"
done

echo ""
echo "=== Kill + relaunch with --rerun-incomplete ==="
for s in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

declare -A TARGETS
TARGETS[test-sentdhipmr-3x]="produce_sentdhipmr_vcf produce_snv_concordances produce_alignstats"
TARGETS[test-sentdhuomr-3x]="produce_sentdhuomr_vcf produce_snv_concordances produce_alignstats"
TARGETS[test-sentdhupmr-3x]="produce_sentdhupmr_vcf produce_snv_concordances produce_alignstats"

for SESSION in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$SESSION/daylily-omics-analysis"
    tmux new-session -d -s "$SESSION"
    tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run ${TARGETS[$SESSION]} -p -k -j 20 -T 1 --rerun-incomplete 2>&1 | tee /tmp/${SESSION}_run2.log" Enter
    echo "Launched: $SESSION"
done

echo "=== Done ==="

