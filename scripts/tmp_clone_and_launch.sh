#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=15 ubuntu@${HEADNODE}"

echo "=== Step 1: Clone t5-mod-ilmn-ont-3x ==="
$SSH "bash -l -c 'day-clone -t feat/modular-hybrid-workflows -w ssh -d t5-mod-ilmn-ont-3x 2>&1 | tail -5'"

echo ""
echo "=== Step 2: Clone t5-mod-ug-ont-3x ==="
$SSH "bash -l -c 'day-clone -t feat/modular-hybrid-workflows -w ssh -d t5-mod-ug-ont-3x 2>&1 | tail -5'"

echo ""
echo "=== Step 3: Verify clones ==="
$SSH "cd /fsx/analysis_results/ubuntu/t5-mod-ilmn-ont-3x/daylily-omics-analysis && git log --oneline -1 && echo '---' && cd /fsx/analysis_results/ubuntu/t5-mod-ug-ont-3x/daylily-omics-analysis && git log --oneline -1"

echo ""
echo "=== Step 4: Launch Modular ILMN+ONT dry-run (hg38) ==="
$SSH "tmux new-session -d -s t5-mod-ilmn-ont && \
  tmux send-keys -t t5-mod-ilmn-ont 'cd /fsx/analysis_results/ubuntu/t5-mod-ilmn-ont-3x/daylily-omics-analysis && source dyoainit && source bin/day_activate slurm hg38 && bin/day_run produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -k -j 2 -T 1 -n 2>&1 | tee /tmp/t5-mod-ilmn-ont.log' Enter"

echo ""
echo "=== Step 5: Launch Modular UG+ONT dry-run (hg38_broad) ==="
$SSH "tmux new-session -d -s t5-mod-ug-ont && \
  tmux send-keys -t t5-mod-ug-ont 'cd /fsx/analysis_results/ubuntu/t5-mod-ug-ont-3x/daylily-omics-analysis && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -k -j 2 -T 1 -n 2>&1 | tee /tmp/t5-mod-ug-ont.log' Enter"

echo ""
echo "=== Step 6: Verify tmux sessions ==="
sleep 3
$SSH "tmux ls 2>/dev/null | grep t5-mod"

echo ""
echo "=== Done (dry-run mode: -n). Review output, then re-run without -n to execute. ==="

