#!/usr/bin/env python3
"""Check the ONT CRAM files and symlinks."""

script = r"""#!/usr/bin/env bash
set -o pipefail
cd /fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis

echo '=== R0 ONT CRAM symlink ==='
ls -la results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram 2>&1
ls -la results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram.crai 2>&1

echo '=== R0 readlink ==='
readlink -f results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram 2>&1

echo '=== R0 target exists? ==='
target=$(readlink -f results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram 2>/dev/null)
ls -la "$target" 2>&1
file "$target" 2>&1

echo '=== R0 samtools view -H (no ref) ==='
samtools view -H results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram 2>&1 | head -5

echo '=== R0 samtools view -H (with ref) ==='
samtools view -H -T /fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram 2>&1 | head -5

echo '=== pre_prep_ont log R0 ==='
cat results/day/hg38_broad/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/logs/R0-HG003-SR1x-LR1x-0-D0-PCR-FREE-ILMN-NOVASEQ.cram.log 2>&1
"""

with open("/tmp/check_cram.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes")

