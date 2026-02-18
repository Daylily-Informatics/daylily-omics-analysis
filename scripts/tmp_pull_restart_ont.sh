#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@${HEADNODE}"

echo "=== Check existing mod ONT tmux sessions ==="
$SSH "for s in io-mod-run uo-mod-run t3-hybrid-mod-ilmn-ont-3x t3-hybrid-mod-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x hm-io-3x hm-uo-3x; do
  echo \"--- \$s ---\"
  tmux capture-pane -t \$s -p 2>/dev/null | tail -5 || echo 'session not found or empty'
  echo ''
done"

