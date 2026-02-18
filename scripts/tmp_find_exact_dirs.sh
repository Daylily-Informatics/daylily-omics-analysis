#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@${HEADNODE}"

echo "=== Analysis dirs ==="
$SSH "ls /fsx/analysis_results/daylily/ 2>/dev/null | head -30 || echo 'not there'; echo '---'; find /fsx -maxdepth 4 -name 't3-hybrid*' -type d 2>/dev/null | head -5; find /fsx -maxdepth 4 -name 't4-hybrid*' -type d 2>/dev/null | head -5"

echo ""
echo "=== day-clone help (destination/clone_root) ==="
$SSH "source ~/.bashrc && day-clone --help 2>&1 | grep -A2 'clone.root\|destination\|CLONE_ROOT'"

