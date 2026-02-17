#!/bin/bash
# Launch all HG003 1x and 3x workflows
# Creates 16 analysis directories (8 workflows x 2 coverages)
set -euo pipefail

BASE_DIR="/fsx/analysis_results/ubuntu/agbt-1x-3x"
BRANCH="feat/modular-hybrid-workflows"
REPO="git@github.com:Daylily-Informatics/daylily-omics-analysis.git"
MANIFEST_DIR=".test_data/data/agbt_2026/1x_3x"

# Workflow definitions: name, target, units_dir
declare -A WORKFLOWS=(
    ["ilmn-solo"]="produce_snv_concordances ilmn-solo"
    ["pacbio-solo"]="produce_snv_concordances pacbio-solo"
    ["ultima-solo"]="produce_snv_concordances ultima-solo"
    ["ont-solo"]="produce_snv_concordances ont-solo"
    ["hybrid-cli-ilmn-ont"]="sentdhio_snv hybrid-cli-ilmn-ont"
    ["hybrid-cli-ultima-ont"]="sentdhuo_snv hybrid-cli-ultima-ont"
    ["hybrid-mod-ilmn-ont"]="sentdhiom_snv hybrid-mod-ilmn-ont"
    ["hybrid-mod-ultima-ont"]="sentdhuom_snv hybrid-mod-ultima-ont"
)

COVERAGES=("1x" "3x")

mkdir -p "$BASE_DIR"

for WF_NAME in "${!WORKFLOWS[@]}"; do
    read -r TARGET UNITS_DIR <<< "${WORKFLOWS[$WF_NAME]}"
    
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
        
        # Create tmux session and launch
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
        tmux new-session -d -s "$TMUX_SESSION" -c "${ANALYSIS_DIR}/daylily-omics-analysis"
        
        # Send the init and run commands
        tmux send-keys -t "$TMUX_SESSION" "cd ${ANALYSIS_DIR}/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project agbt_2026 && dy-a slurm hg38_broad && dy-r ${TARGET} -p -k -j 300 2>&1 | tee ${ANALYSIS_DIR}/${WF_NAME}-${COV}.log" Enter
        
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

