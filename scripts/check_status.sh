#!/bin/bash
# Check status of running tests
echo "=== SLURM Queue ==="
squeue -u ubuntu --format='%.8i %.9P %.30j %.8T %.10M %.4C' | head -30

echo ""
echo "=== tmux sessions ==="
tmux ls 2>/dev/null | grep "^test-" | head -15

