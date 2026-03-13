#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== CHECK $(date) ==="
echo ""

$SSH $HN "for s in t3-hybrid-cli-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x; do echo \"===== \$s =====\"; tmux capture-pane -t \$s -p -S -30 2>/dev/null | grep -E 'steps.*done|SUCCESS|FAIL|Error|Submitted|Exiting|Womp|Finished|rule |jobid:|produce_' | tail -10; echo; done"

echo ""
echo "=== SLURM QUEUE ==="
$SSH $HN "squeue -u ubuntu --format='%.8i %.2t %.45j %.10M' 2>/dev/null | head -15"

