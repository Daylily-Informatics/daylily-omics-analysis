#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
source ~/.bashrc 2>/dev/null

cd $BASEDIR

echo '=== Snakemake log (check config from last run) ==='
head -100 .snakemake/log/2026-02-21T142201.156967.snakemake.log 2>/dev/null | grep -E 'Config|config|aligners|callers|dedupers|snv_caller' | head -20

echo ''
echo '=== Check what callers are in snv_CALLERS ==='
grep -r 'snv_callers' config/*.yaml 2>/dev/null | head -10
grep -r 'sentdhiomr\|sentdhiom\|sentdhio' config/*.yaml 2>/dev/null | head -10

echo ''
echo '=== Check .snakemake/metadata for caller info ==='
ls .snakemake/ 2>/dev/null | head -10

echo ''
echo '=== Day profile config ==='
cat config/day_profiles/slurm_hg38_broad/config.yaml 2>/dev/null | head -30
"

