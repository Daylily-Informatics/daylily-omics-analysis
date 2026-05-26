#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
command -v squeue >/dev/null
command -v tmux >/dev/null

WORKDIR="/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_ilmn20x_ont5x_1022/daylily-omics-analysis"
SESSION="hg003a_altair3_hiomr_ilmn20x_ont5x_1022_run1024"
RC_FILE="/tmp/hg003a_altair3_hiomr_ilmn20x_ont5x_1022.run1024.rc"
REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DS-003 heartbeat status."
    echo "workdir=${WORKDIR}"
    echo "session=${SESSION}"
    echo
    echo "rc_file=${RC_FILE}"
    test -f "${RC_FILE}" && cat "${RC_FILE}" || echo "rc_file_absent"
    echo
    echo "markers"
    find "${WORKDIR}" -maxdepth 1 \( -name 'daylily.successful_run' -o -name 'daylily.failed_run' -o -name 'daylily.failed_run.*' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TS %f\n' 2>/dev/null | LC_ALL=C sort || true
    echo
    echo "tmux"
    if tmux has-session -t "${SESSION}" 2>/dev/null; then
        window_count=$(tmux list-windows -t "${SESSION}" -F '#{window_index}' | wc -l)
        pane_count=$(tmux list-panes -a -F '#{session_name}' | awk -v s="${SESSION}" '$1 == s {n++} END {print n + 0}')
        echo "window_count=${window_count}"
        echo "pane_count=${pane_count}"
        tmux capture-pane -pt "${SESSION}" -S -80 || true
    else
        echo "tmux_session_absent"
    fi
    echo
    echo "squeue"
    squeue -u ubuntu
    echo
    echo "controllers"
    ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}' | head -60
    echo
    echo "fsx"
    df -h /fsx
    echo
    echo "latest_snakemake_log"
    if test -d "${WORKDIR}/.snakemake/log"; then
        latest=$(find "${WORKDIR}/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {print $2}')
        echo "latest=${latest:-}"
        if test -n "${latest:-}"; then
            grep -E '^[0-9]+ of [0-9]+ steps|Error in rule|MissingOutputException|MissingInputException|WorkflowError|FAILED|Exiting because' "${latest}" | tail -40 || true
        fi
    fi
    echo
    echo "daylily_run_tail"
    test -f "${WORKDIR}/daylily_run_1024.log" && tail -120 "${WORKDIR}/daylily_run_1024.log" || true
} | tee -a "${REVIEW_LOG}"
