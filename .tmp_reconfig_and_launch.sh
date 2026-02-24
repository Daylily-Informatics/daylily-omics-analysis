#!/bin/bash
set -euo pipefail
HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
CLONE="/fsx/analysis_results/ubuntu/hiomr_xfer_shard_chr21_20260221/daylily-omics-analysis"
TMUX_SESSION="hiomr_xfer_shard_test"

echo "=== Re-apply config: units.tsv ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "cp /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/config/units.tsv $CLONE/config/units.tsv && echo 'units.tsv copied'"

echo "=== Re-apply config: chr21-only in rule_config template ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "sed -i 's/hg38_broad_sentdhio_chrms: \"1-24\"/hg38_broad_sentdhio_chrms: \"21\"/' $CLONE/config/day_profiles/slurm/templates/rule_config.yaml && grep 'hg38_broad_sentdhio_chrms' $CLONE/config/day_profiles/slurm/templates/rule_config.yaml"

echo "=== Remove active config so it re-copies from templates ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "rm -f $CLONE/config/day_profiles/slurm/rule_config.yaml 2>/dev/null; echo 'active config removed for re-gen'"

echo "=== Re-launch in tmux ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux kill-session -t $TMUX_SESSION 2>/dev/null; tmux new-session -d -s $TMUX_SESSION"

ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux send-keys -t $TMUX_SESSION 'cd $CLONE && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf produce_snv_concordances produce_alignstats -p -k -j 76 -T 0' Enter"

echo "=== Launched ==="

