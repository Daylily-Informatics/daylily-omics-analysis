#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
command -v squeue >/dev/null

REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Parallel DS compact heartbeat."
    echo "fsx"
    df -h /fsx
    echo "squeue_counts"
    squeue -h -u ubuntu -o '%T' | sort | uniq -c || true
    echo "controllers"
    ps -fu ubuntu | awk '/snakemake/ && !/awk/ {profile=""; j=""; for (i=1; i<=NF; i++) { if ($i ~ /^--profile=/) profile=$i; if ($i == "-j") j=$(i+1); } print $2, profile, "j=" j}'
    for spec in \
        "DS-003 hg003a_altair3_hiomr_ilmn20x_ont5x_1022 /tmp/hg003a_altair3_hiomr_ilmn20x_ont5x_1022.run1024.rc" \
        "DS-004 hg003a_altair3_hiomr_ilmn15x_ont10x_1022 /tmp/hg003a_altair3_hiomr_ilmn15x_ont10x_1022.run1024_j190.rc" \
        "DS-005 hg003a_altair3_hiomr_ilmn15x_ont7x_1022 /tmp/hg003a_altair3_hiomr_ilmn15x_ont7x_1022.run1024_j190.rc"
    do
        set -- ${spec}
        ds="$1"
        workdir_name="$2"
        rc_file="$3"
        repo="/fsx/analysis_results/ubuntu/${workdir_name}/daylily-omics-analysis"
        echo "run ${ds} ${workdir_name}"
        test -f "${rc_file}" && cat "${rc_file}" || echo "rc_file_absent"
        echo "markers"
        find "${repo}" -maxdepth 1 \( -name 'daylily.successful_run' -o -name 'daylily.failed_run' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TS %f\n' 2>/dev/null | sort || true
        latest=$(find "${repo}/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')
        echo "latest=${latest:-}"
        if test -n "${latest:-}"; then
            grep -E '^[0-9]+ of [0-9]+ steps|Error in rule|MissingOutputException|MissingInputException|WorkflowError|FAILED|Exiting because' "${latest}" | tail -8 || true
        fi
    done
} | tee -a "${REVIEW_LOG}"
