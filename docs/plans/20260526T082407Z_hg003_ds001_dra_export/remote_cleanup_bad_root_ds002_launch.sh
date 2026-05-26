#!/usr/bin/env bash
set -euo pipefail

SESSION="hg003a_altair3_hiomr_ilmn20x_ont7x_1022_run1024"
ROOT_CONFIG="/fsx/analysis_results/ubuntu/config"
RC_FILE="/tmp/hg003a_altair3_hiomr_ilmn20x_ont7x_1022.run1024.rc"
REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

tmux kill-session -t "${SESSION}" 2>/dev/null || true
rm -rf -- "${ROOT_CONFIG}"
rm -f -- "${RC_FILE}"

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Removed failed root-owned DS-002 tmux launch artifacts before ubuntu relaunch."
    echo "removed_root_tmux=${SESSION}"
    echo "removed_root_config=${ROOT_CONFIG}"
    echo "removed_rc_file=${RC_FILE}"
} | tee -a "${REVIEW_LOG}"
