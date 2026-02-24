#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== Removing stale concordance outputs ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$d/daylily-omics-analysis"
    echo "--- $d ---"
    rm -f "$DIR/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    find "$DIR/results/" -path '*concordance*' -type f -size 0 -delete 2>/dev/null || true
    find "$DIR/results/" -name '*concordance*gather*' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name '*concordance*done*' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name '*concordance*compile*' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*vcfeval*' -type d -empty -delete 2>/dev/null || true
    echo "  Cleaned"
done

echo ""
echo "=== Killing old tmux sessions ==="
for s in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

echo ""
echo "=== Relaunching produce_snv_concordances ==="

for SESSION in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$SESSION/daylily-omics-analysis"
    tmux new-session -d -s "$SESSION"
    tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 20 -T 1 2>&1 | tee /tmp/${SESSION}_conc.log" Enter
    echo "Launched: $SESSION"
done

echo "=== Done ==="

