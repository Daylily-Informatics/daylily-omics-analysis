#!/usr/bin/env bash
#
# rerun_concordance_completed_tests.sh
#
# Pull latest code and re-run concordance for completed hybrid tests that
# had empty snv_callers config due to missing auto-detection in bin/day_run.
#
# Usage: Run from Mac terminal with SSH access to headnode
#   chmod +x scripts/rerun_concordance_completed_tests.sh
#   ./scripts/rerun_concordance_completed_tests.sh
#

set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
SSH_KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
BRANCH="feat/modular-hybrid-workflows"
BASE_DIR="/fsx/analysis_results/ubuntu"

# Tests that completed but need concordance re-run with proper snv_callers
# Format: "test_name:genome_build:snv_caller:aligner"
# The snv_caller and aligner must match the hybrid workflow output
declare -a TESTS=(
    "test-hybrid-mod-ilmn-ont-3x:hg38:sentdhiom:ont"
    "test-hybrid-mod-ilmn-pb-3x:hg38:sentdhipm:sentmm2"
    "test-hybrid-cli-ilmn-pb-3x:hg38:sentdhip:sentmm2"
    "test-hybrid-cli-ug-pb-3x:hg38_broad:sentdhup:sentmm2"
)

echo "=============================================="
echo "Re-running concordance for completed tests"
echo "=============================================="
echo ""

for entry in "${TESTS[@]}"; do
    IFS=':' read -r test_name genome_build snv_caller aligner <<< "$entry"

    echo ">>> Processing: $test_name (genome: $genome_build, snv: $snv_caller, alnr: $aligner)"

    # Create a tmux session for this test's concordance run
    tmux_session="${test_name}-conc"

    # Build the command with EXPLICIT config for snv_callers and aligners
    # This ensures produce_snv_concordances knows which caller/aligner pair to check
    cmd="cd ${BASE_DIR}/${test_name}/daylily-omics-analysis && \
git fetch origin ${BRANCH} && \
git checkout ${BRANCH} && \
git pull origin ${BRANCH} && \
source ~/.bashrc && \
source dyoainit --project ${test_name} && \
source bin/day_activate slurm ${genome_build} && \
bin/day_run produce_snv_concordances -p -k -j 10 --config aligners=\"['${aligner}']\" snv_callers=\"['${snv_caller}']\" 2>&1 | tee /tmp/${test_name}-concordance.log"

    echo "    Killing existing tmux session if present..."
    ssh -i "$SSH_KEY" "$HEADNODE" "tmux kill-session -t $tmux_session 2>/dev/null || true"

    echo "    Creating tmux session: $tmux_session"
    ssh -i "$SSH_KEY" "$HEADNODE" "tmux new-session -d -s $tmux_session 'bash'"

    echo "    Sending concordance command..."
    ssh -i "$SSH_KEY" "$HEADNODE" "tmux send-keys -t $tmux_session '$cmd' Enter"

    echo "    ✓ Started concordance for $test_name"
    echo ""

    # Small delay between launches
    sleep 2
done

echo "=============================================="
echo "All concordance jobs launched!"
echo ""
echo "Monitor with:"
echo "  ssh -i $SSH_KEY $HEADNODE 'for t in ${TESTS[*]%:*}; do echo \"=== \$t ===\"; tmux capture-pane -t \$t-conc -p 2>/dev/null | tail -5; done'"
echo ""
echo "Or check individual sessions:"
for entry in "${TESTS[@]}"; do
    IFS=':' read -r test_name _ _ <<< "$entry"
    echo "  ssh -i $SSH_KEY $HEADNODE 'tmux attach -t ${test_name}-conc'"
done
echo "=============================================="

