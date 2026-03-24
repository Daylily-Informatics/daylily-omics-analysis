#!/usr/bin/env python3
"""Check units.tsv ONT columns for R0/R1."""

script = r"""#!/usr/bin/env bash
set -o pipefail
cd /fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis

echo '=== units.tsv header ==='
head -1 config/units.tsv

echo '=== R0 line ==='
grep '^R0' config/units.tsv

echo '=== R1 line ==='
grep '^R1' config/units.tsv

echo '=== column count ==='
head -1 config/units.tsv | awk -F'\t' '{print NF, "columns"}'

echo '=== ONT columns (by name) ==='
head -1 config/units.tsv | tr '\t' '\n' | grep -ni 'ont\|lr\|long\|nanopore\|cram_path'
"""

with open("/tmp/check_units.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

