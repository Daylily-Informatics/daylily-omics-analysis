#!/bin/bash
# Monitor all 15 tests and report status
export PATH=/opt/slurm/bin:$PATH

echo "=== $(date) ==="
echo ""

# Count running/pending jobs (excluding sleep_test)
running=$(squeue -u ubuntu --format='%.40j' | grep -v sleep_test | grep -v NAME | wc -l)
echo "Active SLURM jobs (excluding sleep_test): $running"
echo ""

if [ "$running" -gt 0 ]; then
    echo "=== SLURM Queue ==="
    squeue -u ubuntu --format='%.8i %.9P %.45j %.8T %.10M %.4C' | grep -v sleep_test | head -50
    echo ""
fi

# Check each tmux session for errors
echo "=== Test Session Status ==="
for sess in $(tmux ls 2>/dev/null | grep "^test-" | cut -d: -f1); do
    output=$(tmux capture-pane -t "$sess" -p 2>/dev/null | tail -30)
    
    # Check for errors
    if echo "$output" | grep -qiE "error|failed|exception|traceback"; then
        echo "❌ $sess - HAS ERRORS:"
        echo "$output" | grep -iE "error|failed|exception|traceback" | tail -5
    elif echo "$output" | grep -qE "Nothing to be done|complete"; then
        echo "✅ $sess - COMPLETE"
    elif echo "$output" | grep -q "Submitted job"; then
        last_job=$(echo "$output" | grep "Submitted job" | tail -1)
        echo "🔄 $sess - RUNNING ($last_job)"
    else
        echo "⏳ $sess - INITIALIZING"
    fi
done

echo ""
echo "=== Summary ==="
echo "Jobs in queue: $running"

