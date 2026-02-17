#!/bin/bash
# Quick status check for 3x tests
echo "=== TMUX Sessions ==="
tmux ls 2>/dev/null || echo "No tmux sessions"
echo ""
echo "=== SLURM Queue ==="
squeue -u ubuntu --format="%.8i %.9P %.30j %.8T %.10M" 2>/dev/null | head -25
echo ""
echo "=== Test Directories ==="
ls -d /fsx/analysis_results/ubuntu/test-*-3x 2>/dev/null | wc -l
echo "directories"

