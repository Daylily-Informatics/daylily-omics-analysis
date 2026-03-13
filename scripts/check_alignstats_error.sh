#!/bin/bash
# Check alignstats error details

echo "=== test-hybrid-cli-ilmn-ont-3x alignstats output ==="
tmux capture-pane -t test-hybrid-cli-ilmn-ont-3x -p 2>/dev/null | grep -i -B5 -A5 "alignstats"

echo ""
echo "=== Check if ALIGNSTATSCOMPLEFAILED file exists ==="
ls -la /fsx/analysis_results/ubuntu/test-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/logs/ALIGNSTATS* 2>/dev/null

echo ""
echo "=== Check alignstats log files ==="
find /fsx/analysis_results/ubuntu/test-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/results -name "*alignstats*log*" 2>/dev/null | head -5 | while read f; do
    echo "--- $f ---"
    tail -20 "$f" 2>/dev/null
done

