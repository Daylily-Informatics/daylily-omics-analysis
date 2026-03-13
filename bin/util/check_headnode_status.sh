#!/bin/bash
# Check workflow status on headnode
# Usage: ./bin/util/check_headnode_status.sh

PEM="${PEM:-~/.ssh/lsmc-omics-us-west-2.pem}"
HEADNODE="${HEADNODE:-44.231.76.175}"

ssh -o StrictHostKeyChecking=no -i "$PEM" ubuntu@"$HEADNODE" '
echo "=== TMUX Sessions ==="
tmux ls 2>/dev/null | head -30

echo ""
echo "=== Slurm Queue ==="
squeue -u ubuntu -o "%.8i %.12P %.50j %.8T %.6M" 2>/dev/null | head -50

echo ""
echo "=== ilmn-solo-1x status ==="
tmux capture-pane -t ilmn-solo-1x -p -S -15 2>/dev/null | tail -10

echo ""
echo "=== ilmn-solo-3x status ==="
tmux capture-pane -t ilmn-solo-3x -p -S -15 2>/dev/null | tail -10
'

