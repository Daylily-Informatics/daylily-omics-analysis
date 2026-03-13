#!/bin/bash
set -e
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"

STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Pull on STD clone ==="
ssh -i "$PEM" "$HOST" "cd $STD_DIR && git pull --rebase origin feat/modular-hybrid-workflows 2>&1"

echo ""
echo "=== Pull on REF clone ==="
ssh -i "$PEM" "$HOST" "cd $REF_DIR && git pull --rebase origin feat/modular-hybrid-workflows 2>&1"

echo ""
echo "=== Kill old tmux sessions ==="
ssh -i "$PEM" "$HOST" "tmux kill-session -t hiom_std_chr21 2>/dev/null; tmux kill-session -t hiom_ref_chr21 2>/dev/null; echo 'old sessions killed'"

echo ""
echo "=== Start STD pipeline ==="
ssh -i "$PEM" "$HOST" "tmux new-session -d -s hiom_std_chr21 && tmux send-keys -t hiom_std_chr21 'cd $STD_DIR && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiom_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_std_chr21.log' Enter"
echo "STD pipeline launched in tmux session hiom_std_chr21"

echo ""
echo "=== Start REF pipeline ==="
ssh -i "$PEM" "$HOST" "tmux new-session -d -s hiom_ref_chr21 && tmux send-keys -t hiom_ref_chr21 'cd $REF_DIR && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_ref_chr21.log' Enter"
echo "REF pipeline launched in tmux session hiom_ref_chr21"

echo ""
echo "=== Done. Check status in ~5 min ==="

