#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== PULL IN CLI UG+ONT ==="
$SSH $HN "cd /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -5 && echo && git log --oneline -2"

echo ""
echo "=== PULL IN MOD ILMN+ONT ==="
$SSH $HN "cd /fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -5 && echo && git log --oneline -2"

echo ""
echo "=== CLI UG+ONT: remove old sort.vcf.gz and unlock ==="
$SSH $HN "cd /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis && rm -f results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/*.sort.vcf* && rm -rf .snakemake/locks && echo 'Cleaned CLI UG+ONT'"

echo ""
echo "=== MOD ILMN+ONT: remove old tmp VCFs (from pre-fix 2-sample pass1) and unlock ==="
$SSH $HN "cd /fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis && rm -f results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/*.vcf.gz* && rm -f results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/*.vcf && rm -rf .snakemake/locks && echo 'Cleaned MOD ILMN+ONT'"

echo ""
echo "=== RESTART CLI UG+ONT ==="
$SSH $HN "tmux send-keys -t t3-hybrid-cli-ug-ont-3x 'cd /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project t3-cli-ug-ont-restart && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf -p -k -j 300' Enter && echo 'Sent restart to CLI UG+ONT'"

echo ""
echo "=== RESTART MOD ILMN+ONT ==="
$SSH $HN "tmux send-keys -t t4-hybrid-mod-ilmn-ont-3x 'cd /fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project t4-mod-ilmn-ont-restart && source bin/day_activate slurm hg38 && bin/day_run produce_sentdhiom_vcf -p -k -j 300' Enter && echo 'Sent restart to MOD ILMN+ONT'"

echo ""
echo "=== ALL RESTARTS SENT ==="

