#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
source ~/.bashrc 2>/dev/null
export PATH=/home/ubuntu/miniconda3/envs/SAM/bin:\$PATH

echo '=== CLI concordance data from agbt analysis ==='
find /fsx/analysis_results/ubuntu/ -path '*agbt*' -name 'giab_concordance_mqc.tsv' 2>/dev/null | head -5

echo ''
echo '=== Check for _analysis_data concordance files locally ==='
find /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/_analysis_data/ -name '*concordance*' 2>/dev/null | head -10

echo ''
echo '=== CLI reference concordance from cmr-hio-cli ==='
find /fsx/analysis_results/ubuntu/cmr-hio-cli-20260218-163021/ -name 'giab_concordance_mqc.tsv' 2>/dev/null | head -5

echo ''
echo '=== Check if sentdhio can be run from this analysis dir ==='
cd /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis
grep -c 'sentdhio' config/samples.tsv 2>/dev/null || echo 'no samples.tsv'
grep -l 'sentdhio' workflow/rules/*.smk 2>/dev/null | head -5

echo ''
echo '=== What callers are configured? ==='
cat config/samples.tsv 2>/dev/null | head -3
"

