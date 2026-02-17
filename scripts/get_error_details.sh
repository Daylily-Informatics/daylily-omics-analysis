#!/bin/bash
# Get detailed error info from failing tests

echo "=== test-hybrid-cli-ilmn-pb-3x (MissingInputException) ==="
tmux capture-pane -t test-hybrid-cli-ilmn-pb-3x -p 2>/dev/null | grep -A5 "MissingInputException"
echo ""

echo "=== test-hybrid-cli-ug-pb-3x (MissingInputException) ==="
tmux capture-pane -t test-hybrid-cli-ug-pb-3x -p 2>/dev/null | grep -A5 "MissingInputException"
echo ""

echo "=== test-hybrid-mod-ilmn-pb-3x (MissingInputException) ==="
tmux capture-pane -t test-hybrid-mod-ilmn-pb-3x -p 2>/dev/null | grep -A5 "MissingInputException"
echo ""

echo "=== test-hybrid-mod-roche-ont-3x (MissingInputException) ==="
tmux capture-pane -t test-hybrid-mod-roche-ont-3x -p 2>/dev/null | grep -A5 "MissingInputException"
echo ""

echo "=== test-hybrid-mod-roche-pb-3x (MissingInputException) ==="
tmux capture-pane -t test-hybrid-mod-roche-pb-3x -p 2>/dev/null | grep -A5 "MissingInputException"
echo ""

echo "=== test-hybrid-mod-ug-ont-3x (mapq0_bed error) ==="
cat /fsx/analysis_results/ubuntu/test-hybrid-mod-ug-ont-3x/daylily-omics-analysis/results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuom/log/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA.ug.na.1-24.mapq0_bed.log 2>/dev/null | tail -30

