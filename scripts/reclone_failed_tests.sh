#!/usr/bin/env bash
# Re-clone failed test directories with the correct branch and restart tests
set -e

BRANCH="feat/modular-hybrid-workflows"
BASE_DIR="/fsx/analysis_results/ubuntu"

# Kill existing tmux sessions for these tests
echo "=== Killing existing tmux sessions ==="
for sess in test-hybrid-cli-ilmn-pb-3x test-hybrid-mod-ilmn-pb-3x test-hybrid-cli-ug-pb-3x test-hybrid-mod-ug-pb-3x test-hybrid-mod-roche-ont-3x test-hybrid-mod-roche-pb-3x; do
    tmux kill-session -t "$sess" 2>/dev/null && echo "Killed $sess" || true
done

# Function to clone and setup a test
clone_and_start() {
    local test_name="$1"
    local manifest_src="$2"
    local command="$3"
    local genome="$4"
    
    echo ""
    echo "=== Setting up $test_name ==="
    
    # Remove old directory if exists
    if [ -d "${BASE_DIR}/${test_name}" ]; then
        echo "Removing old ${test_name}..."
        rm -rf "${BASE_DIR}/${test_name}"
    fi
    
    # Clone with day-clone
    echo "Cloning with day-clone..."
    day-clone -w ssh -t "$BRANCH" -d "$test_name"
    
    # Copy manifest files
    echo "Copying manifest files from ${manifest_src}..."
    cp "${BASE_DIR}/${test_name}/${manifest_src}/samples.tsv" "${BASE_DIR}/${test_name}/config/"
    cp "${BASE_DIR}/${test_name}/${manifest_src}/units.tsv" "${BASE_DIR}/${test_name}/config/"
    
    # Create tmux session and start test
    echo "Starting test in tmux session..."
    tmux new-session -d -s "$test_name"
    tmux send-keys -t "$test_name" "cd ${BASE_DIR}/${test_name} && source ~/.bashrc && source dyoainit --project ${test_name} && source bin/day_activate slurm ${genome} && ${command} 2>&1 | tee /tmp/${test_name}.log" Enter
    
    echo "Started $test_name"
}

# PacBio hybrids need sentmm2 alignment first
# CLI ILMN+PB (hg38)
clone_and_start "test-hybrid-cli-ilmn-pb-3x" \
    ".test_data/data/hybrid/ilmn_pb/hg003/3x" \
    "bin/day_run produce_sentmm2_align_sort produce_sentdhip_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1" \
    "hg38"

# MOD ILMN+PB (hg38)
clone_and_start "test-hybrid-mod-ilmn-pb-3x" \
    ".test_data/data/hybrid/ilmn_pb/hg003/3x" \
    "bin/day_run produce_sentmm2_align_sort produce_sentdhipm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1" \
    "hg38"

# CLI UG+PB (hg38_broad)
clone_and_start "test-hybrid-cli-ug-pb-3x" \
    ".test_data/data/hybrid/ug_pb/hg003/3x" \
    "bin/day_run produce_sentmm2_align_sort produce_sentdhup_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1" \
    "hg38_broad"

# MOD UG+PB (hg38_broad)
clone_and_start "test-hybrid-mod-ug-pb-3x" \
    ".test_data/data/hybrid/ug_pb/hg003/3x" \
    "bin/day_run produce_sentmm2_align_sort produce_sentdhupm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1" \
    "hg38_broad"

# Roche hybrids
# MOD Roche+ONT (hg38)
clone_and_start "test-hybrid-mod-roche-ont-3x" \
    ".test_data/data/hybrid/roche_ont/hg003/3x" \
    "bin/day_run produce_sentdhrom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1" \
    "hg38"

# MOD Roche+PB (hg38) - needs sentmm2 for PB alignment
clone_and_start "test-hybrid-mod-roche-pb-3x" \
    ".test_data/data/hybrid/roche_pb/hg003/3x" \
    "bin/day_run produce_sentmm2_align_sort produce_sentdhrpm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1" \
    "hg38"

echo ""
echo "=== All tests re-cloned and started ==="
tmux ls 2>/dev/null | grep test- || echo "No test sessions found"

