#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"

WORKDIR_NAME="hg003a_altair3_hiomr_ilmn20x_ont5x_1022"
SESSION="${WORKDIR_NAME}_run1024"
ROOT="/fsx/analysis_results/ubuntu"
WORKDIR="${ROOT}/${WORKDIR_NAME}"
REPO_DIR="${WORKDIR}/daylily-omics-analysis"
MANIFEST_ROOT="/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z"
SAMPLES="${MANIFEST_ROOT}/hiomr_ilmn20x_ont5x_samples.tsv"
UNITS="${MANIFEST_ROOT}/hiomr_ilmn20x_ont5x_units.tsv"
REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"
RC_FILE="/tmp/${WORKDIR_NAME}.run1024.rc"

test -f "${SAMPLES}"
test -f "${UNITS}"
test ! -e "${WORKDIR}"
if tmux has-session -t "${SESSION}" 2>/dev/null; then
    echo "tmux session already exists: ${SESSION}" >&2
    exit 2
fi

tmux new-session -d -s "${SESSION}"
window_count=$(tmux list-windows -t "${SESSION}" -F '#{window_index}' | wc -l)
pane_count=$(tmux list-panes -a -F '#{session_name}' | awk -v s="${SESSION}" '$1 == s {n++} END {print n + 0}')
test "${window_count}" -eq 1
test "${pane_count}" -eq 1

tmux send-keys -t "${SESSION}" "cd ${ROOT}" Enter
tmux send-keys -t "${SESSION}" "day-clone -t 1.0.24 -d ${WORKDIR_NAME}" Enter
tmux send-keys -t "${SESSION}" "cd ${REPO_DIR}" Enter
tmux send-keys -t "${SESSION}" "mkdir -p ./config" Enter
tmux send-keys -t "${SESSION}" "cp ${SAMPLES} ./config/samples.tsv" Enter
tmux send-keys -t "${SESSION}" "cp ${UNITS} ./config/units.tsv" Enter
tmux send-keys -t "${SESSION}" "source dyoainit" Enter
tmux send-keys -t "${SESSION}" "dy-a slurm hg38_broad" Enter
tmux send-keys -t "${SESSION}" "dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=[\"dmd\"]' -p -j 234 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 > daylily_run_1024.log 2>&1; echo __DS003_RUN1024_RC__:\$? | tee ${RC_FILE}" Enter

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DS-003 launch queued in tmux ${SESSION} at tag 1.0.24."
    echo "workdir=${WORKDIR}"
    echo "samples=${SAMPLES}"
    echo "units=${UNITS}"
    echo "rc_file=${RC_FILE}"
    df -h /fsx
    squeue -u ubuntu || true
} | tee -a "${REVIEW_LOG}"

tmux capture-pane -pt "${SESSION}" -S -80
