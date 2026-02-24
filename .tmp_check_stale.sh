#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Verify units.tsv on headnode (STD) ==="
ssh -i "$KEY" "$HN" "awk -F'\t' 'NR==2{print \"ILMN_TRIM_READ_LENGTH: [\" \$18 \"]\"}' $STD_DIR/.test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/units.tsv"

echo "=== Verify units.tsv on headnode (REF) ==="
ssh -i "$KEY" "$HN" "awk -F'\t' 'NR==2{print \"ILMN_TRIM_READ_LENGTH: [\" \$18 \"]\"}' $REF_DIR/.test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/units.tsv"

echo ""
echo "=== Check sr_align rule log for actual error (STD) ==="
ssh -i "$KEY" "$HN" "tail -20 $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/log/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.21.sr_align.log 2>/dev/null || echo 'no log'"

echo ""
echo "=== Check slurm stderr for job 5751 (STD) ==="
ssh -i "$KEY" "$HN" "ls -lt $STD_DIR/logs/slurm/sentdhiom_sr_align/ 2>/dev/null | head -5"
ssh -i "$KEY" "$HN" "cat \$(ls -t $STD_DIR/logs/slurm/sentdhiom_sr_align/*.err 2>/dev/null | head -1) 2>/dev/null | tail -20 || echo 'no slurm err'"

echo ""
echo "=== Full clean and restart needed ==="
echo "The jobs ran with stale cached scripts. Need to wipe .snakemake entirely and restart."

