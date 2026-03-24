#!/usr/bin/env python3
"""Generate script to check slurm logs v2."""

script = r"""#!/usr/bin/env bash
set -o pipefail
cd /fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis

echo '=== slurm log dirs ==='
find logs/slurm/ -type d 2>/dev/null

echo '=== slurm log files ==='
find logs/slurm/ -type f 2>/dev/null | head -30

echo '=== slurm accounting ==='
export PATH=/opt/slurm/bin:$PATH
sacct -u ubuntu --format=JobID,JobName%50,State,ExitCode,Elapsed,MaxRSS --starttime=2026-03-23 2>/dev/null | head -40

echo '=== pass1 detailed log (R0) last 50 lines ==='
tail -50 results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/log/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.ont.na.1-24.pass1.log 2>&1

echo '=== snakemake log (latest) ==='
ls -lt .snakemake/log/*.log 2>/dev/null | head -3
"""

with open("/tmp/check_slurm2.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

