#!/bin/bash
# Check output from first few tmux sessions
for sess in test-ont-solo-3x test-ilmn-solo-3x test-hybrid-cli-ilmn-ont-3x; do
    echo "=== $sess ==="
    tmux capture-pane -t "$sess" -p 2>/dev/null | tail -20
    echo ""
done

echo "=== SLURM Queue (via sq alias) ==="
sq 2>/dev/null || echo "sq alias not available"

