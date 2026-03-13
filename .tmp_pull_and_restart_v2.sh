#!/usr/bin/env bash
set -euo pipefail

SSH="ssh -i $HOME/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175"

STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Pull on both clones ==="
$SSH "cd $STD_DIR && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -3 && echo '--- STD pulled ---' && cd $REF_DIR && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -3 && echo '--- REF pulled ---'"

echo ""
echo "=== Clean snakemake state ==="
$SSH "cd $STD_DIR && rm -rf .snakemake/incomplete .snakemake/locks 2>/dev/null; cd $REF_DIR && rm -rf .snakemake/incomplete .snakemake/locks 2>/dev/null; echo 'Cleaned'"

echo ""
echo "=== Kill existing tmux sessions ==="
$SSH "tmux kill-session -t hiom_std_chr21 2>/dev/null || true; tmux kill-session -t hiom_ref_chr21 2>/dev/null || true; echo 'Sessions killed'"

echo ""
echo "=== Cancel any leftover slurm jobs ==="
$SSH "export PATH=/opt/slurm/bin:\$PATH; squeue -u ubuntu --format='%i %j' --noheader 2>/dev/null | while read jid jname; do echo \"Cancelling \$jid (\$jname)\"; scancel \$jid; done; echo 'All cancelled'"

echo ""
echo "=== Verify fix applied (sample awk block) ==="
$SSH "grep -c '@RG\"{{' $STD_DIR/workflow/rules/sent_hybrid_ilmn_ont_modular.smk && grep -c '@RG\"{{' $REF_DIR/workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk"

echo ""
echo "=== Start STD pipeline ==="
$SSH "tmux new-session -d -s hiom_std_chr21 && tmux send-keys -t hiom_std_chr21 'cd $STD_DIR && source ~/.bashrc && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiom_vcf -p -k -j 20 --config aligners=\"[\\\"ont\\\"]\" snv_callers=\"[\\\"sentdhiom\\\"]\" 2>&1 | tee /tmp/hiom_std_chr21.log' Enter"

echo ""
echo "=== Start REF pipeline ==="
$SSH "tmux new-session -d -s hiom_ref_chr21 && tmux send-keys -t hiom_ref_chr21 'cd $REF_DIR && source ~/.bashrc && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf -p -k -j 20 --config aligners=\"[\\\"ont\\\"]\" snv_callers=\"[\\\"sentdhiomr\\\"]\" 2>&1 | tee /tmp/hiom_ref_chr21.log' Enter"

echo ""
echo "=== Done — both pipelines restarted ==="

