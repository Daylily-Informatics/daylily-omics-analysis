#!/usr/bin/env python3
"""Generate a check script for validation outputs."""

script = r"""#!/usr/bin/env bash
set -o pipefail
cd /fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis

echo '=== PHASE 1: Output File Check ==='

echo '--- SNV VCFs ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*.snv.vcf.gz 2>&1
ls -lh results/day/hg38_broad/R1-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*.snv.vcf.gz 2>&1

echo '--- SV VCFs ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*.sv.vcf.gz 2>&1
ls -lh results/day/hg38_broad/R1-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*.sv.vcf.gz 2>&1

echo '--- CNV VCFs ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*.cnv.vcf.gz 2>&1
ls -lh results/day/hg38_broad/R1-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*.cnv.vcf.gz 2>&1

echo '--- SEGDUP ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*segdup* 2>&1
ls -lh results/day/hg38_broad/R1-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*segdup* 2>&1

echo '--- MITO ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*mito* 2>&1
ls -lh results/day/hg38_broad/R1-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/*mito* 2>&1

echo '--- MANTA ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/sv/manta/ 2>&1

echo '--- TMP intermediates ---'
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/tmp/sr_aligned.bam 2>&1
ls -lh results/day/hg38_broad/R0-*/align/ont/na/snv/sentdhiomr/vcfs/1-24/tmp/sr_dedup.bam 2>&1

echo '--- Phase1 log errors ---'
grep -cE 'Error executing rule|RuleException|Traceback' /tmp/val_logs/real_phase1_all.log 2>&1
grep -E 'Error executing rule' /tmp/val_logs/real_phase1_all.log 2>&1

echo '--- Phase1 summary ---'
grep -E '^[0-9]+ of [0-9]+ steps' /tmp/val_logs/real_phase1_all.log 2>&1
grep 'RETURN CODE' /tmp/val_logs/real_phase1_all.log 2>&1

echo '--- Phase2 log errors ---'
grep -E 'Error executing rule|MissingInputException' /tmp/val_logs/real_phase2_sr.log 2>&1

echo '--- Phase2 summary ---'
grep -E '^[0-9]+ of [0-9]+ steps' /tmp/val_logs/real_phase2_sr.log 2>&1
grep 'RETURN CODE' /tmp/val_logs/real_phase2_sr.log 2>&1
"""

with open("/tmp/check_outputs.sh", "w") as f:
    f.write(script)
print(f"Written {len(script)} bytes to /tmp/check_outputs.sh")

