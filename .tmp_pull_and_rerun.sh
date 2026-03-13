#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== Pull on all 3 dirs ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    echo "--- $d ---"
    cd "$BASE/$d/daylily-omics-analysis"
    git pull origin feat/modular-hybrid-workflows 2>&1 | tail -3
    git log --oneline -1
done

echo ""
echo "=== Re-copy test data ==="

echo "--- sentdhipmr (ILMN+PB) ---"
D="$BASE/test-sentdhipmr-3x/daylily-omics-analysis"
cp "$D/.test_data/data/hybrid/ilmn_pb/hg003/3x/samples.tsv" "$D/config/samples.tsv"
cp "$D/.test_data/data/hybrid/ilmn_pb/hg003/3x/units.tsv" "$D/config/units.tsv"
echo "  copied"

echo "--- sentdhuomr (UG+ONT) ---"
D="$BASE/test-sentdhuomr-3x/daylily-omics-analysis"
cp "$D/.test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv" "$D/config/samples.tsv"
cp "$D/.test_data/data/hybrid/ug_ont/hg003/3x/units.tsv" "$D/config/units.tsv"
echo "  copied"

echo "--- sentdhupmr (UG+PB) ---"
D="$BASE/test-sentdhupmr-3x/daylily-omics-analysis"
cp "$D/.test_data/data/hybrid/ug_pb/hg003/3x/samples.tsv" "$D/config/samples.tsv"
cp "$D/.test_data/data/hybrid/ug_pb/hg003/3x/units.tsv" "$D/config/units.tsv"
echo "  copied"

echo ""
echo "=== Kill old tmux sessions ==="
for s in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    tmux kill-session -t "$s" 2>/dev/null && echo "killed $s" || echo "$s already gone"
done

echo ""
echo "=== Launch dry-runs ==="

SESSION="test-sentdhipmr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhipmr_vcf produce_snv_concordances produce_alignstats -p -k -j 20 -T 1 -n 2>&1 | tee /tmp/${SESSION}_dryrun.log" Enter
echo "Launched: $SESSION"

SESSION="test-sentdhuomr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhuomr_vcf produce_snv_concordances produce_alignstats -p -k -j 20 -T 1 -n 2>&1 | tee /tmp/${SESSION}_dryrun.log" Enter
echo "Launched: $SESSION"

SESSION="test-sentdhupmr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhupmr_vcf produce_snv_concordances produce_alignstats -p -k -j 20 -T 1 -n 2>&1 | tee /tmp/${SESSION}_dryrun.log" Enter
echo "Launched: $SESSION"

echo ""
echo "=== Done. Check results with: tmux ls ==="

