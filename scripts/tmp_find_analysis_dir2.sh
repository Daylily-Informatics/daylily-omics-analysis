#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@${HEADNODE}"

echo "=== /fsx/analysis_results contents ==="
$SSH "ls -d /fsx/analysis_results/*hybrid* 2>/dev/null || echo 'none'; echo '---'; ls /fsx/analysis_results/ 2>/dev/null | head -20"

echo ""
echo "=== Check day-clone location ==="
$SSH "source ~/.bashrc && which day-clone 2>/dev/null && day-clone --help 2>&1 | head -10 || echo 'day-clone not found'"

echo ""
echo "=== tmux sessions ==="
$SSH "tmux ls 2>/dev/null || echo 'no tmux sessions'"

