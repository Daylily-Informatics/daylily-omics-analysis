#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
command -v day-clone >/dev/null
command -v tmux >/dev/null
command -v squeue >/dev/null

ROOT="/fsx/analysis_results/ubuntu"
MANIFEST_ROOT="/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z"
REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

launch_one() {
    local ds_id="$1"
    local workdir_name="$2"
    local manifest_prefix="$3"
    local session="${workdir_name}_run1024_j190"
    local workdir="${ROOT}/${workdir_name}"
    local repo_dir="${workdir}/daylily-omics-analysis"
    local samples="${MANIFEST_ROOT}/${manifest_prefix}_samples.tsv"
    local units="${MANIFEST_ROOT}/${manifest_prefix}_units.tsv"
    local rc_file="/tmp/${workdir_name}.run1024_j190.rc"

    test -f "${samples}"
    test -f "${units}"
    test ! -e "${workdir}"
    if tmux has-session -t "${session}" 2>/dev/null; then
        echo "tmux session already exists: ${session}" >&2
        exit 2
    fi

    tmux new-session -d -s "${session}"
    window_count=$(tmux list-windows -t "${session}" -F '#{window_index}' | wc -l)
    pane_count=$(tmux list-panes -a -F '#{session_name}' | awk -v s="${session}" '$1 == s {n++} END {print n + 0}')
    test "${window_count}" -eq 1
    test "${pane_count}" -eq 1

    tmux send-keys -t "${session}" "cd ${ROOT}" Enter
    tmux send-keys -t "${session}" "day-clone -t 1.0.24 -d ${workdir_name}" Enter
    tmux send-keys -t "${session}" "cd ${repo_dir}" Enter
    tmux send-keys -t "${session}" "mkdir -p ./config" Enter
    tmux send-keys -t "${session}" "cp ${samples} ./config/samples.tsv" Enter
    tmux send-keys -t "${session}" "cp ${units} ./config/units.tsv" Enter
    tmux send-keys -t "${session}" "source dyoainit" Enter
    tmux send-keys -t "${session}" "dy-a slurm hg38_broad" Enter
    tmux send-keys -t "${session}" "dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=[\"dmd\"]' -p -j 190 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 > daylily_run_1024_j190.log 2>&1; echo __${ds_id}_RUN1024_J190_RC__:\$? | tee ${rc_file}" Enter

    {
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${ds_id} launch queued in tmux ${session} at tag 1.0.24 with -j 190."
        echo "workdir=${workdir}"
        echo "samples=${samples}"
        echo "units=${units}"
        echo "rc_file=${rc_file}"
    } | tee -a "${REVIEW_LOG}"
}

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] User-approved concurrency change: target up to 3 active downsample analyses; new launches use -j 190."
    echo "prelaunch_fsx"
    df -h /fsx
    echo "prelaunch_squeue"
    squeue -u ubuntu
    echo "prelaunch_workdirs"
    find "${ROOT}" -maxdepth 1 -mindepth 1 -printf '%f\t%y\n' | sort
} | tee -a "${REVIEW_LOG}"

launch_one "DS004" "hg003a_altair3_hiomr_ilmn15x_ont10x_1022" "hiomr_ilmn15x_ont10x"
launch_one "DS005" "hg003a_altair3_hiomr_ilmn15x_ont7x_1022" "hiomr_ilmn15x_ont7x"

sleep 45

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Parallel launch verification for DS-004 and DS-005."
    echo "postlaunch_fsx"
    df -h /fsx
    echo "postlaunch_squeue"
    squeue -u ubuntu
    echo "postlaunch_controllers"
    ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}' | head -100
    echo "postlaunch_workdirs"
    find "${ROOT}" -maxdepth 1 -mindepth 1 -printf '%f\t%y\n' | sort
    for session in \
        hg003a_altair3_hiomr_ilmn15x_ont10x_1022_run1024_j190 \
        hg003a_altair3_hiomr_ilmn15x_ont7x_1022_run1024_j190
    do
        echo
        echo "tmux_capture=${session}"
        tmux capture-pane -pt "${session}" -S -80 || true
    done
} | tee -a "${REVIEW_LOG}"
