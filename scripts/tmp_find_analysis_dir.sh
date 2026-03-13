#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@${HEADNODE}"

echo "=== Finding analysis dirs ==="
$SSH "source ~/.bashrc && ls /fsx/ 2>/dev/null || echo 'no /fsx'; ls /fsx/resources/ 2>/dev/null | head -5 || true; find / -maxdepth 3 -name 't3-hybrid*' -type d 2>/dev/null | head -5; find / -maxdepth 3 -name 't4-hybrid*' -type d 2>/dev/null | head -5"

