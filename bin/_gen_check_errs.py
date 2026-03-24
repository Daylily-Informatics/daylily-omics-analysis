#!/usr/bin/env python3
"""Check slurm .err files for pass1."""

script = r"""#!/usr/bin/env bash
set -o pipefail
cd /fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis

echo '=== pass1 err R0 ==='
cat logs/slurm/sentdhiomr_pass1/sentdhiomr_pass1.R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.27.err 2>&1

echo '=== pass1 err R1 ==='
cat logs/slurm/sentdhiomr_pass1/sentdhiomr_pass1.R1-HG003-SR1x-LR3x-1-D0-PCR-FREE-ILMN-NOVASEQ.69.err 2>&1

echo '=== sr_align err R0 ==='
cat logs/slurm/sentdhiomr_sr_align/sentdhiomr_sr_align.R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.4.err 2>&1 | tail -20

echo '=== sr_markdup err R0 ==='
cat logs/slurm/sentdhiomr_sr_markdup/sentdhiomr_sr_markdup.R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.3.err 2>&1 | tail -20

echo '=== pre_prep_ont err R0 ==='
cat logs/slurm/pre_prep_ont_cram/pre_prep_ont_cram.R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.6.err 2>&1 | tail -20

echo '=== merge_sr_bams check ==='
find logs/slurm/sentdhiomr_merge_sr_bams -type f 2>/dev/null | head -10
echo '=== sentdhiomr_sr_dedup check ==='
find logs/slurm/sentdhiomr_sr_dedup -type f 2>/dev/null | head -10
"""

with open("/tmp/check_errs.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

