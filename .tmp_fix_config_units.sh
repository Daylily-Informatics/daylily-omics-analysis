#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Show current config/units.tsv on STD ==="
ssh -i "$KEY" "$HN" "cat -A $STD_DIR/config/units.tsv | head -3"

echo ""
echo "=== Fix config/units.tsv on STD (replace 19 with na in col 18) ==="
ssh -i "$KEY" "$HN" "cd $STD_DIR && awk -F'\t' -v OFS='\t' 'NR==1{print; next} {if(\$18==\"19\") \$18=\"na\"; print}' config/units.tsv > config/units.tsv.tmp && mv config/units.tsv.tmp config/units.tsv && echo STD_FIX_OK"

echo ""
echo "=== Verify STD fix ==="
ssh -i "$KEY" "$HN" "awk -F'\t' 'NR==2{print \"col18: [\" \$18 \"]\"}' $STD_DIR/config/units.tsv"

echo ""
echo "=== Show current config/units.tsv on REF ==="
ssh -i "$KEY" "$HN" "awk -F'\t' 'NR==2{print \"col18: [\" \$18 \"]\"}' $REF_DIR/config/units.tsv"

echo ""
echo "=== Fix config/units.tsv on REF ==="
ssh -i "$KEY" "$HN" "cd $REF_DIR && awk -F'\t' -v OFS='\t' 'NR==1{print; next} {if(\$18==\"19\") \$18=\"na\"; print}' config/units.tsv > config/units.tsv.tmp && mv config/units.tsv.tmp config/units.tsv && echo REF_FIX_OK"

echo ""
echo "=== Verify REF fix ==="
ssh -i "$KEY" "$HN" "awk -F'\t' 'NR==2{print \"col18: [\" \$18 \"]\"}' $REF_DIR/config/units.tsv"

echo ""
echo "=== Cancel running jobs and clean ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && scancel 5753 5754 2>/dev/null; echo CANCEL_OK"
ssh -i "$KEY" "$HN" "cd $STD_DIR && rm -rf .snakemake && rm -rf results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/ && echo STD_CLEAN_OK"
ssh -i "$KEY" "$HN" "cd $REF_DIR && rm -rf .snakemake && rm -rf results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/ && echo REF_CLEAN_OK"

echo ""
echo "=== Restart both pipelines ==="
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_std_chr21 C-c"
sleep 1
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_std_chr21 'cd $STD_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiom_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_std_chr21.log' Enter"

sleep 1
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_ref_chr21 C-c"
sleep 1
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_ref_chr21 'cd $REF_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_ref_chr21.log' Enter"

echo ""
echo "=== DONE - both restarted with fixed config/units.tsv ==="

