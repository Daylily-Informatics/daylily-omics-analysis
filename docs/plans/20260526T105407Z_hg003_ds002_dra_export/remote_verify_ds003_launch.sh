#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"

WORKDIR="/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_ilmn20x_ont5x_1022/daylily-omics-analysis"
SESSION="hg003a_altair3_hiomr_ilmn20x_ont5x_1022_run1024"
REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DS-003 launch verification."
    echo "tmux_capture=${SESSION}"
    tmux capture-pane -pt "${SESSION}" -S -120 || true
    echo
    test -d "${WORKDIR}" && echo "workdir_present=1" || echo "workdir_present=0"
    test -f "${WORKDIR}/daylily_run_1024.log" && tail -80 "${WORKDIR}/daylily_run_1024.log" || true
    echo
    squeue -u ubuntu || true
    echo
    ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}' | head -40
    echo
    df -h /fsx
} | tee -a "${REVIEW_LOG}"
