#!/bin/bash
# Check status of all running tests
# Run this ON THE HEADNODE

echo "=== Test Status Summary ==="
echo ""

for session in test-ilmn-5x-run test-ont-5x-run test-pb-5x-run test-ultima-5x-run test-hybrid-io-5x-run test-hybrid-uo-5x-run test-hybrid-io-mod-5x-run test-hybrid-uo-mod-5x-run; do
    echo "--- $session ---"
    tmux capture-pane -t "$session" -p 2>/dev/null | grep -E 'Job stats|total|done|Submitted|ERROR|Nothing to be done|100%|of [0-9]+|SUCCESS|awry' | tail -3
done 2>/dev/null

echo ""
echo "=== Slurm Queue ==="
/opt/slurm/bin/squeue -u ubuntu --format='%.8i %.42j %.8T %.10M'

