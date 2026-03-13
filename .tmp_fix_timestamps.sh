#!/bin/bash
set -e
cd /fsx/analysis_results/ubuntu/gatk-fullon/daylily-omics-analysis

echo "=== Removing .snakemake metadata ==="
rm -rf .snakemake
echo "Done removing .snakemake"

echo "=== Touching files in dependency order ==="

# 1. First touch all alignment BAM files
echo "Step 1: alignment outputs"
find results/day/hg38 -name "*.sent.bam" -type f 2>/dev/null | while read f; do
  touch "$f" && echo "  touched $f"
done
sleep 2

# 2. Touch dedup BAM/CRAM (not in gatk subdir)
echo "Step 2: dedup outputs"
find results/day/hg38 -path "*/dmd/*" -name "*.bam" -type f 2>/dev/null | grep -v "/snv/" | while read f; do
  touch "$f" && echo "  touched $f"
done
sleep 2

# 3. Touch BSQR recal tables
echo "Step 3: BSQR recal tables"
find results/day/hg38 -name "*.bsqr.recal_data.table" -type f 2>/dev/null | while read f; do
  touch "$f" && echo "  touched $f"
done
sleep 2

# 4. Touch BSQR recal CRAMs and indexes
echo "Step 4: BSQR CRAMs"
find results/day/hg38 -name "*.bsqr.recal.cram*" -type f 2>/dev/null | while read f; do
  touch "$f" && echo "  touched $f"
done
sleep 2

# 5. Touch final VCFs and indexes (last)
echo "Step 5: Final VCFs"
find results/day/hg38 -name "*.gatk.snv.sort.vcf.gz" -type f 2>/dev/null | while read f; do
  touch "$f" && echo "  touched $f"
done
sleep 1
find results/day/hg38 -name "*.gatk.snv.sort.vcf.gz.tbi" -type f 2>/dev/null | while read f; do
  touch "$f" && echo "  touched $f"
done

echo "=== Done ==="

