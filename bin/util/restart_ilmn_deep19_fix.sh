#!/bin/bash
# Restart ilmn-solo workflows with the deep19 fix
set -euo pipefail

cd /tmp/launch-1x-3x
git fetch origin
git reset --hard origin/feat/modular-hybrid-workflows

# Kill existing ilmn-solo sessions
tmux kill-session -t ilmn-solo-1x 2>/dev/null || true
tmux kill-session -t ilmn-solo-3x 2>/dev/null || true

for COV in 1x 3x; do
    ADIR="/fsx/analysis_results/ubuntu/agbt-1x-3x/ilmn-solo-${COV}"
    cd "${ADIR}/daylily-omics-analysis"
    git fetch origin
    git reset --hard origin/feat/modular-hybrid-workflows
    
    cp ".test_data/data/agbt_2026/1x_3x/HG003.samples.tsv" config/samples.tsv
    cp ".test_data/data/agbt_2026/1x_3x/ilmn-solo/HG003_${COV}.units.tsv" config/units.tsv
    
    tmux new-session -d -s "ilmn-solo-${COV}" -c "${ADIR}/daylily-omics-analysis"
    
    tmux send-keys -t "ilmn-solo-${COV}" "cd ${ADIR}/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project agbt_2026 && source bin/day_activate slurm hg38_broad && source bin/day_run produce_bwa2a_align produce_dmd_dedup_cram produce_deep19_snv_vcf produce_snv_concordances -p -k -j 300" Enter
    
    echo "Launched ilmn-solo-${COV}"
    sleep 2
done

echo ""
tmux ls | grep ilmn-solo || true
