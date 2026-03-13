#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "========================================"
echo "=== TMUX STATUS FOR ALL 4 TESTS ==="
echo "========================================"
$SSH $HN "for s in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x t3-hybrid-mod-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x; do echo \"===== \$s =====\"; tmux capture-pane -t \$s -p -S -30 2>/dev/null | grep -E 'steps.*done|SUCCESS|FAIL|Error|Submitted|Exiting|Womp|Finished' | tail -5; echo; done"

echo ""
echo "========================================"
echo "=== SLURM QUEUE ==="
echo "========================================"
$SSH $HN "squeue -u ubuntu --format='%.8i %.2t %.55j %.10M' 2>/dev/null | head -20"

echo ""
echo "========================================"
echo "=== FIND HAP.PY / CONCORDANCE RESULTS ==="
echo "========================================"

# CLI ILMN+ONT (known passing)
echo "--- CLI ILMN+ONT ---"
$SSH $HN "find /fsx/analysis_results/ubuntu/t3-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/results -name '*happy*' -o -name '*concordance*' -o -name '*hc*summary*' -o -name '*giab*' 2>/dev/null | head -10"

# Mod UG+ONT (known passing)
echo "--- MOD UG+ONT ---"
$SSH $HN "find /fsx/analysis_results/ubuntu/t3-hybrid-mod-ug-ont-3x/daylily-omics-analysis/results -name '*happy*' -o -name '*concordance*' -o -name '*hc*summary*' -o -name '*giab*' 2>/dev/null | head -10"

# CLI UG+ONT (restarted)
echo "--- CLI UG+ONT ---"
$SSH $HN "find /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results -name '*happy*' -o -name '*concordance*' -o -name '*hc*summary*' -o -name '*giab*' 2>/dev/null | head -10"

# Mod ILMN+ONT (restarted)
echo "--- MOD ILMN+ONT ---"
$SSH $HN "find /fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis/results -name '*happy*' -o -name '*concordance*' -o -name '*hc*summary*' -o -name '*giab*' 2>/dev/null | head -10"

