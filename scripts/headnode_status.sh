#!/bin/bash
# Check headnode status
set -e
SSH_KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HEADNODE="ubuntu@44.231.76.175"

ssh -i "$SSH_KEY" "$HEADNODE" 'echo "=== TMUX ===" && tmux ls 2>/dev/null || echo "No sessions" && echo "=== SQUEUE ===" && squeue -u ubuntu 2>/dev/null | head -20 && echo "=== TEST DIRS ===" && ls -d /fsx/analysis_results/ubuntu/test-*-3x 2>/dev/null | wc -l'

