#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
command -v squeue >/dev/null
command -v tmux >/dev/null

REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

check_run() {
    local ds_id="$1"
    local workdir_name="$2"
    local session="$3"
    local rc_file="$4"
    local run_log="$5"
    local workdir="/fsx/analysis_results/ubuntu/${workdir_name}/daylily-omics-analysis"

    echo
    echo "RUN ${ds_id}"
    echo "workdir=${workdir}"
    echo "session=${session}"
    echo "rc_file=${rc_file}"
    test -f "${rc_file}" && cat "${rc_file}" || echo "rc_file_absent"
    echo "markers"
    find "${workdir}" -maxdepth 1 \( -name 'daylily.successful_run' -o -name 'daylily.failed_run' -o -name 'daylily.failed_run.*' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TS %f\n' 2>/dev/null | LC_ALL=C sort || true
    echo "tmux"
    if tmux has-session -t "${session}" 2>/dev/null; then
        window_count=$(tmux list-windows -t "${session}" -F '#{window_index}' | wc -l)
        pane_count=$(tmux list-panes -a -F '#{session_name}' | awk -v s="${session}" '$1 == s {n++} END {print n + 0}')
        echo "window_count=${window_count}"
        echo "pane_count=${pane_count}"
    else
        echo "tmux_session_absent"
    fi
    echo "latest_snakemake_log"
    if test -d "${workdir}/.snakemake/log"; then
        latest=$(find "${workdir}/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {print $2}')
        echo "latest=${latest:-}"
        if test -n "${latest:-}"; then
            grep -E '^[0-9]+ of [0-9]+ steps|Error in rule|MissingOutputException|MissingInputException|WorkflowError|FAILED|Exiting because' "${latest}" | tail -20 || true
        fi
    fi
    echo "run_log_tail"
    test -f "${workdir}/${run_log}" && tail -30 "${workdir}/${run_log}" || true
}

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Parallel DS heartbeat status."
    echo "host=$(hostname) user=$(id -un)"
    echo
    echo "fsx"
    df -h /fsx
    echo
    echo "squeue"
    squeue -u ubuntu -o '%i %.9T %.12M %.30j %.12P %.20R'
    echo
    echo "squeue_counts"
    squeue -h -u ubuntu -o '%T' | sort | uniq -c || true
    echo
    echo "controllers"
    ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}' | head -120
    echo
    echo "workdirs"
    find /fsx/analysis_results/ubuntu -maxdepth 1 -mindepth 1 -printf '%f\t%y\n' | sort
    check_run "DS-003" "hg003a_altair3_hiomr_ilmn20x_ont5x_1022" "hg003a_altair3_hiomr_ilmn20x_ont5x_1022_run1024" "/tmp/hg003a_altair3_hiomr_ilmn20x_ont5x_1022.run1024.rc" "daylily_run_1024.log"
    check_run "DS-004" "hg003a_altair3_hiomr_ilmn15x_ont10x_1022" "hg003a_altair3_hiomr_ilmn15x_ont10x_1022_run1024_j190" "/tmp/hg003a_altair3_hiomr_ilmn15x_ont10x_1022.run1024_j190.rc" "daylily_run_1024_j190.log"
    check_run "DS-005" "hg003a_altair3_hiomr_ilmn15x_ont7x_1022" "hg003a_altair3_hiomr_ilmn15x_ont7x_1022_run1024_j190" "/tmp/hg003a_altair3_hiomr_ilmn15x_ont7x_1022.run1024_j190.rc" "daylily_run_1024_j190.log"
} | tee -a "${REVIEW_LOG}"
