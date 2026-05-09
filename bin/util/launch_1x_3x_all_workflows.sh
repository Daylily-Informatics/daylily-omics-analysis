#!/bin/bash
# Launch all HG003 1x and 3x workflows
# Creates 16 analysis directories (8 workflows x 2 coverages)
set -euo pipefail

BASE_DIR="/fsx/analysis_results/ubuntu/agbt-1x-3x"
BRANCH="feat/modular-hybrid-workflows"
REPO="git@github.com:lsmc-bio/daylily-omics-analysis.git"
MANIFEST_DIR=".test_data/data/agbt_2026/1x_3x"

# Workflow definitions: name, target, config_args, units_dir
# For ILMN solo: need aligners, dedupers, snv_callers
# For platform-specific: use produce_*_vcf targets
# NOTE: Config args use single quotes around the whole list to avoid shell parsing issues
declare -A WORKFLOWS=(
    ["ilmn-solo"]="produce_snv_concordances|--config aligners=[bwa2a] dedupers=[dppl] snv_callers=[deep19]|ilmn-solo"
    ["pacbio-solo"]="produce_sentdpb_vcf||pacbio-solo"
    ["ultima-solo"]="produce_sentdug_vcf||ultima-solo"
    ["ont-solo"]="produce_sentdont_vcf||ont-solo"
    ["hybrid-cli-ilmn-ont"]="produce_sentdhio_vcf||hybrid-cli-ilmn-ont"
    ["hybrid-cli-ultima-ont"]="produce_sentdhuo_vcf||hybrid-cli-ultima-ont"
    ["hybrid-mod-ilmn-ont"]="produce_sentdhiom_vcf||hybrid-mod-ilmn-ont"
    ["hybrid-mod-ultima-ont"]="produce_sentdhuom_vcf||hybrid-mod-ultima-ont"
)

COVERAGES=("1x" "3x")

mkdir -p "$BASE_DIR"

for WF_NAME in "${!WORKFLOWS[@]}"; do
    # Parse pipe-delimited: TARGET|CONFIG_ARGS|UNITS_DIR
    IFS='|' read -r TARGET CONFIG_ARGS UNITS_DIR <<< "${WORKFLOWS[$WF_NAME]}"

    for COV in "${COVERAGES[@]}"; do
        ANALYSIS_DIR="${BASE_DIR}/${WF_NAME}-${COV}"
        TMUX_SESSION="${WF_NAME}-${COV}"

        echo "=== Setting up ${WF_NAME} ${COV} ==="

        # Clone if not exists
        if [ ! -d "${ANALYSIS_DIR}/daylily-omics-analysis" ]; then
            mkdir -p "$ANALYSIS_DIR"
            cd "$ANALYSIS_DIR"
            git clone "$REPO" daylily-omics-analysis
            cd daylily-omics-analysis
            git checkout "$BRANCH"
        else
            cd "${ANALYSIS_DIR}/daylily-omics-analysis"
            git fetch origin
            git reset --hard origin/$BRANCH
        fi

        # Copy manifest files
        cp "${MANIFEST_DIR}/HG003.samples.tsv" config/samples.tsv
        cp "${MANIFEST_DIR}/${UNITS_DIR}/HG003_${COV}.units.tsv" config/units.tsv

        echo "  Manifest: ${UNITS_DIR}/HG003_${COV}.units.tsv"
        echo "  Target: ${TARGET}"
        echo "  Config: ${CONFIG_ARGS:-none}"

        # Create tmux session and launch
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
        tmux new-session -d -s "$TMUX_SESSION" -c "${ANALYSIS_DIR}/daylily-omics-analysis"

        # Build the run command - use source bin/day_* directly (aliases may not be available)
        RUN_CMD="cd ${ANALYSIS_DIR}/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project agbt_2026 && source bin/day_activate slurm hg38_broad && source bin/day_run ${TARGET} -p -k -j 300 ${CONFIG_ARGS} 2>&1 | tee ${ANALYSIS_DIR}/${WF_NAME}-${COV}.log"

        tmux send-keys -t "$TMUX_SESSION" "$RUN_CMD" Enter

        echo "  Launched in tmux: ${TMUX_SESSION}"
        echo ""

        # Small delay to avoid overwhelming git/slurm
        sleep 2
    done
done

echo "=== All 16 workflows launched ==="
echo ""
echo "Monitor with: tmux ls"
echo "Check queue:  squeue -u ubuntu -o '%.8i %.20P %.30j %.8T %.10M'"

