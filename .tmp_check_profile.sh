#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
source ~/.bashrc 2>/dev/null
cd $BASEDIR

echo '=== Profile dirs ==='
ls -la config/day_profiles/ 2>/dev/null
echo ''

echo '=== Active profile config ==='
for f in config/day_profiles/slurm_hg38_broad/config.yaml config/day_profiles/slurm_hg38_broad/config.json config/day_profiles/*/config.yaml; do
    if [ -f \"\$f\" ]; then
        echo \"--- \$f ---\"
        cat \"\$f\" 2>/dev/null | head -30
        echo ''
    fi
done

echo '=== Full snakemake log first 50 lines ==='
tail -100 .snakemake/log/2026-02-21T142201.156967.snakemake.log 2>/dev/null | head -50

echo ''
echo '=== tmux capture from hiomr_ref_run (check the command that was run) ==='
tmux capture-pane -t hiomr_ref_run -p -S -200 2>/dev/null | grep -E 'day_run|day_activate|snv_callers|aligners|produce_' | head -10
"

