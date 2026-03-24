#!/usr/bin/env python3
"""Generate script to check slurm logs for pass1 failures."""

script = r"""#!/usr/bin/env bash
set -o pipefail
cd /fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis

echo '=== pass1 slurm logs ==='
for f in logs/slurm/sentdhiomr_pass1/*.out; do
    echo "--- $f ---"
    tail -20 "$f"
done

echo '=== pass1 rule logs ==='
for f in results/day/hg38_broad/R*/align/ont/na/snv/sentdhiomr/log/*.pass1.log; do
    echo "--- $f ---"
    tail -10 "$f"
done

echo '=== sr_align slurm logs ==='
for f in logs/slurm/sentdhiomr_sr_align/*.out; do
    echo "--- $f ---"
    tail -5 "$f"
done

echo '=== sr_dedup slurm logs ==='
for f in logs/slurm/sentdhiomr_sr_dedup/*.out; do
    echo "--- $f ---"
    tail -5 "$f"
done

echo '=== merge_sr_bams slurm logs ==='
for f in logs/slurm/sentdhiomr_merge_sr_bams/*.out logs/slurm/sentdhiomr_merge_sr_bams/*.err; do
    echo "--- $f ---"
    tail -10 "$f" 2>/dev/null
done

echo '=== all results dirs ==='
find results/day/hg38_broad/ -maxdepth 1 -type d 2>/dev/null
"""

with open("/tmp/check_slurm.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

