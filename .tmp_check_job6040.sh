#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
export PATH=/opt/slurm/bin:\$PATH
echo '=== Job 6040 details ==='
scontrol show job 6040 2>&1 | grep -E 'JobName|JobState|RunTime|StdOut|StdErr'
echo ''
echo '=== Job 6043 details ==='
scontrol show job 6043 2>&1 | grep -E 'JobName|JobState|RunTime|StdOut|StdErr'
echo ''
echo '=== Check 6040 log ==='
find /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/logs/slurm/parse_vcfeval_summary_roi/ -name '*6040*' -exec tail -5 {} \; 2>/dev/null
echo ''
echo '=== Check 6043 log ==='
find /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/logs/slurm/parse_vcfeval_summary_roi/ -name '*6043*' -exec tail -5 {} \; 2>/dev/null
"

