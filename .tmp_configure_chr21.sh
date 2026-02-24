#!/bin/bash
set -euo pipefail
HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
CLONE="/fsx/analysis_results/ubuntu/hiomr_xfer_shard_chr21_20260221/daylily-omics-analysis"

ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE << REMOTECMD
set -euo pipefail

echo "=== Copy units.tsv from previous chr21 run ==="
cp /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/config/units.tsv $CLONE/config/units.tsv
echo "units.tsv copied"
cat $CLONE/config/units.tsv | head -3

echo ""
echo "=== Set chr21-only in rule_config ==="
sed -i 's/hg38_broad_sentdhio_chrms: "1-24"/hg38_broad_sentdhio_chrms: "21"/' $CLONE/config/day_profiles/slurm/templates/rule_config.yaml
echo "rule_config patched"
grep "hg38_broad_sentdhio_chrms" $CLONE/config/day_profiles/slurm/templates/rule_config.yaml

echo ""
echo "=== Verify branch commit ==="
cd $CLONE
git log --oneline -1

echo ""
echo "=== Config done ==="
REMOTECMD

