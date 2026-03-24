#!/usr/bin/env python3
"""Check detailed Phase 1 and Phase 2 logs."""

script = r"""#!/usr/bin/env bash
set -o pipefail

echo "=== PHASE 1 LOG (full) ==="
cat /tmp/val_logs/real_phase1_all.log 2>/dev/null | head -200

echo ""
echo "================================================"
echo "=== PHASE 2 LOG (full) ==="
cat /tmp/val_logs/real_phase2_sr.log 2>/dev/null | head -200

echo ""
echo "================================================"
echo "=== ALL LOG FILES IN /tmp/val_logs/ ==="
ls -la /tmp/val_logs/ 2>/dev/null

echo ""
echo "=== SNAKEMAKE LOGS ==="
ADIR="/fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis"
ls -lt "$ADIR"/.snakemake/log/*.log 2>/dev/null | head -5
"""

with open("/tmp/detailed_check.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

