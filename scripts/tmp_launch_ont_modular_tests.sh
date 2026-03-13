#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@${HEADNODE}"

echo "=== Step 1: Clone fresh analysis dirs ==="
$SSH "source ~/.bashrc && \
  cd /fsx/analysis && \
  day-clone --project t5-hybrid-mod-ilmn-ont-3x --branch feat/modular-hybrid-workflows && \
  day-clone --project t5-hybrid-mod-ug-ont-3x --branch feat/modular-hybrid-workflows"

echo ""
echo "=== Step 2: Verify commit on both clones ==="
$SSH "cd /fsx/analysis/t5-hybrid-mod-ilmn-ont-3x && git log --oneline -1 && \
      cd /fsx/analysis/t5-hybrid-mod-ug-ont-3x && git log --oneline -1"

echo ""
echo "=== Step 3: Launch Modular ILMN+ONT test (hg38) ==="
$SSH "tmux new-session -d -s t5-mod-ilmn-ont && \
  tmux send-keys -t t5-mod-ilmn-ont 'cd /fsx/analysis/t5-hybrid-mod-ilmn-ont-3x && source ~/.bashrc && . dyoainit --project t5-hybrid-mod-ilmn-ont-3x && dy-a slurm hg38 && dy-r produce_sentdhiom_vcf -p -k -j 50 2>&1 | tee /tmp/t5-mod-ilmn-ont.log' Enter"

echo ""
echo "=== Step 4: Launch Modular UG+ONT test (hg38_broad) ==="
$SSH "tmux new-session -d -s t5-mod-ug-ont && \
  tmux send-keys -t t5-mod-ug-ont 'cd /fsx/analysis/t5-hybrid-mod-ug-ont-3x && source ~/.bashrc && . dyoainit --project t5-hybrid-mod-ug-ont-3x && dy-a slurm hg38_broad && dy-r produce_sentdhuom_vcf -p -k -j 50 2>&1 | tee /tmp/t5-mod-ug-ont.log' Enter"

echo ""
echo "=== Step 5: Verify tmux sessions ==="
sleep 3
$SSH "tmux ls"

echo ""
echo "=== Done. Two modular ONT tests launched ==="
echo "  t5-mod-ilmn-ont : Modular ILMN+ONT (hg38)"
echo "  t5-mod-ug-ont   : Modular UG+ONT (hg38_broad)"

