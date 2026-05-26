#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
test "$#" -eq 5

workdir_name="$1"
manifest_name="$2"
session_name="$3"
rc_file="$4"
label="$5"

root="/fsx/analysis_results/ubuntu"
manifest_root="/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z"
review_log="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

samples="${manifest_root}/${manifest_name}_samples.tsv"
units="${manifest_root}/${manifest_name}_units.tsv"
workdir="${root}/${workdir_name}"
repo="${workdir}/daylily-omics-analysis"

test -f "${samples}"
test -f "${units}"
test ! -e "${workdir}"
if tmux has-session -t "${session_name}" 2>/dev/null; then
    echo "tmux session already exists: ${session_name}" >&2
    exit 20
fi

active_count="$(
    ps -fu ubuntu \
        | awk '/snakemake|dy-r|day_run/ && /hg003a_altair3_hiomr_/ && !/awk/ {n++} END {print n + 0}'
)"
if [ "${active_count}" -ge 3 ]; then
    echo "active downsample workflow count ${active_count} is already >= 3" >&2
    exit 21
fi

cd "${root}"
day-clone -t 1.0.24 -d "${workdir_name}"
cd "${repo}"
mkdir -p config
cp "${samples}" config/samples.tsv
cp "${units}" config/units.tsv
git describe --tags --always --dirty > .daylily_launch_git_ref.txt

tmux new-session -d -s "${session_name}"
tmux send-keys -t "${session_name}" "cd '${repo}'" Enter
tmux send-keys -t "${session_name}" "source dyoainit" Enter
tmux send-keys -t "${session_name}" "dy-a slurm hg38_broad" Enter
tmux send-keys -t "${session_name}" "dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=[\"dmd\"]' -p -j 190 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 > daylily_run_1024_j190.log 2>&1; echo __${label}_RUN1024_J190_RC__:\$? | tee '${rc_file}'" Enter

sleep 8
windows="$(tmux list-windows -t "${session_name}" -F '#{window_index}' | wc -l | awk '{print $1}')"
panes="$(tmux list-panes -a -F '#{session_name}' | awk -v s="${session_name}" '$1 == s {n++} END {print n + 0}')"
test "${windows}" -eq 1
test "${panes}" -eq 1

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${label} launched: workdir=${workdir_name}, manifest=${manifest_name}, tmux=${session_name}, rc=${rc_file}, -j 190, tag=$(cat .daylily_launch_git_ref.txt)."
    tmux capture-pane -pt "${session_name}" -S -80 | tail -80
    squeue -u ubuntu | head -80
    ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}'
    df -h /fsx
} | tee -a "${review_log}"
