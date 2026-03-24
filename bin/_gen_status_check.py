#!/usr/bin/env python3
"""Generate a status check script for the headnode."""

script = r"""#!/usr/bin/env bash
set -o pipefail
ADIR="/fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis"

echo "=== TMUX SESSIONS ==="
tmux ls 2>&1

echo ""
echo "=== SLURM QUEUE ==="
export PATH=/opt/slurm/bin:$PATH
squeue -u ubuntu 2>&1 | head -30

echo ""
echo "=== VALIDATION LOG TAIL ==="
tail -50 /tmp/val_logs/real_validation_full.log 2>/dev/null || echo "No validation log found"

echo ""
echo "=== SNAKEMAKE LOG (latest) ==="
LATEST_LOG=$(ls -t "$ADIR"/.snakemake/log/*.log 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
    echo "Log: $LATEST_LOG"
    tail -40 "$LATEST_LOG"
else
    echo "No snakemake log found"
fi

echo ""
echo "=== FAILED JOBS ==="
find "$ADIR"/results/ -name "*.log" -newer "$ADIR/dyoainit" -exec grep -l -i "error\|failed\|exception" {} \; 2>/dev/null | head -20

echo ""
echo "=== GIT STATUS ==="
cd "$ADIR" && git log --oneline -3
"""

with open("/tmp/status_check.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

