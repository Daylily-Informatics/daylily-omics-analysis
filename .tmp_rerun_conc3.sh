#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== Pulling latest code on all 3 analysis dirs ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$d/daylily-omics-analysis"
    echo "--- $d ---"
    cd "$DIR"
    git pull origin feat/modular-hybrid-workflows 2>&1 | tail -3
    echo ""
done

echo "=== Removing ALL stale concordance outputs ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$d/daylily-omics-analysis"
    echo "--- $d ---"
    # Remove concordance summary
    rm -f "$DIR/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    # Remove concordance.done sentinels
    find "$DIR/results/" -name 'concordance.done' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name 'concordance.fofn' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name 'concordance.fin.cmds' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name 'concordance.done.SKIPPED' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*concordance*' -name '*.log' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*concordance*' -name '*.bench.tsv' -type f -delete 2>/dev/null || true
    # Remove any vcfeval outputs
    find "$DIR/results/" -path '*vcfeval*' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*vcfeval*' -type d -empty -delete 2>/dev/null || true
    # Remove any per-ROI mqc files
    find "$DIR/results/" -path '*concordance*' -name '*.mqc.tsv' -type f -delete 2>/dev/null || true
    echo "  Cleaned"
done

echo ""
echo "=== Killing old tmux sessions ==="
for s in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

echo ""
echo "=== Launching concordance runs with explicit config ==="

# sentdhipmr: Illumina+PacBio → alnr=sentmm2, snv=sentdhipmr
SESSION="test-sentdhipmr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 20 -T 1 --config aligners=\"['sentmm2']\" snv_callers=\"['sentdhipmr']\" 2>&1 | tee /tmp/${SESSION}_conc3.log" Enter
echo "Launched: $SESSION (sentmm2 + sentdhipmr)"

# sentdhuomr: Ultima+ONT → alnr=ug, snv=sentdhuomr
SESSION="test-sentdhuomr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 20 -T 1 --config aligners=\"['ug']\" snv_callers=\"['sentdhuomr']\" 2>&1 | tee /tmp/${SESSION}_conc3.log" Enter
echo "Launched: $SESSION (ug + sentdhuomr)"

# sentdhupmr: Ultima+PacBio → alnr=ug, snv=sentdhupmr
SESSION="test-sentdhupmr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 20 -T 1 --config aligners=\"['ug']\" snv_callers=\"['sentdhupmr']\" 2>&1 | tee /tmp/${SESSION}_conc3.log" Enter
echo "Launched: $SESSION (ug + sentdhupmr)"

echo "=== Done ==="

