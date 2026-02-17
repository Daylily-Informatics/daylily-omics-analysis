#!/usr/bin/env bash
# Restart all failed hybrid tests with correct dependencies
set -e

# Pull the latest workflow fixes in all affected test directories
echo "=== Pulling workflow fixes in all affected test directories ==="

# List of failed tests that need restarting
FAILED_TESTS=(
    "test-hybrid-cli-ilmn-pb-3x"
    "test-hybrid-mod-ilmn-pb-3x"
    "test-hybrid-cli-ug-pb-3x"
    "test-hybrid-mod-ug-pb-3x"
    "test-hybrid-mod-roche-ont-3x"
    "test-hybrid-mod-roche-pb-3x"
)

BASE_DIR="/fsx/analysis_results/ubuntu"

for test in "${FAILED_TESTS[@]}"; do
    test_dir="${BASE_DIR}/${test}"
    if [ -d "$test_dir" ]; then
        echo "Pulling in $test_dir..."
        cd "$test_dir"
        git pull origin feat/modular-hybrid-workflows || echo "Pull failed for $test"
    else
        echo "Directory not found: $test_dir"
    fi
done

echo ""
echo "=== Restarting PacBio hybrid tests (need sentmm2 alignment first) ==="

# PB hybrids: add sentmm2 alignment target before hybrid target
restart_pb_hybrid() {
    local test_name="$1"
    local hybrid_target="$2"
    local test_dir="${BASE_DIR}/${test_name}"
    
    echo ""
    echo "=== Restarting $test_name ==="
    
    # Kill existing tmux session
    tmux kill-session -t "$test_name" 2>/dev/null || true
    
    # Create new tmux session
    tmux new-session -d -s "$test_name"
    
    # Send the run command - add sentmm2 target to produce PB alignment first
    tmux send-keys -t "$test_name" "cd ${test_dir} && source ~/.bashrc && source dyoainit --project ${test_name} && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentmm2_align_sort ${hybrid_target} produce_alignstats produce_snv_concordances -p -k -j 20 -T 1 2>&1 | tee /tmp/${test_name}.log" Enter
    
    echo "Started $test_name in tmux session"
}

# Restart CLI ILMN+PB
restart_pb_hybrid "test-hybrid-cli-ilmn-pb-3x" "produce_sentdhip_vcf"

# Restart MOD ILMN+PB
restart_pb_hybrid "test-hybrid-mod-ilmn-pb-3x" "produce_sentdhipm_vcf"

# Restart CLI UG+PB
restart_pb_hybrid "test-hybrid-cli-ug-pb-3x" "produce_sentdhup_vcf"

# Restart MOD UG+PB
restart_pb_hybrid "test-hybrid-mod-ug-pb-3x" "produce_sentdhupm_vcf"

echo ""
echo "=== Restarting Roche hybrid tests ==="

restart_roche_hybrid() {
    local test_name="$1"
    local hybrid_target="$2"
    local test_dir="${BASE_DIR}/${test_name}"
    
    echo ""
    echo "=== Restarting $test_name ==="
    
    # Kill existing tmux session
    tmux kill-session -t "$test_name" 2>/dev/null || true
    
    # Create new tmux session
    tmux new-session -d -s "$test_name"
    
    # For Roche tests, we need the pre_prep_roche_bam target first
    # The hybrid workflow now expects .roche.bam files, which come from the staging rule
    tmux send-keys -t "$test_name" "cd ${test_dir} && source ~/.bashrc && source dyoainit --project ${test_name} && source bin/day_activate slurm hg38_broad && bin/day_run ${hybrid_target} produce_alignstats produce_snv_concordances -p -k -j 20 -T 1 2>&1 | tee /tmp/${test_name}.log" Enter
    
    echo "Started $test_name in tmux session"
}

# Restart MOD Roche+ONT
restart_roche_hybrid "test-hybrid-mod-roche-ont-3x" "produce_sentdhrom_vcf"

# For Roche+PB we need both sentmm2 alignment AND Roche BAM staging
echo ""
echo "=== Restarting test-hybrid-mod-roche-pb-3x (needs both sentmm2 and roche staging) ==="
test_name="test-hybrid-mod-roche-pb-3x"
test_dir="${BASE_DIR}/${test_name}"
tmux kill-session -t "$test_name" 2>/dev/null || true
tmux new-session -d -s "$test_name"
tmux send-keys -t "$test_name" "cd ${test_dir} && source ~/.bashrc && source dyoainit --project ${test_name} && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentmm2_align_sort produce_sentdhrpm_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1 2>&1 | tee /tmp/${test_name}.log" Enter
echo "Started $test_name in tmux session"

echo ""
echo "=== All failed hybrid tests restarted ==="
tmux ls 2>/dev/null | grep test- || echo "No test sessions found"

