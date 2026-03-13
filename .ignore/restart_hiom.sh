#!/bin/bash
set -euo pipefail

ADIR="/fsx/analysis_results/ubuntu/cmr-hiom-mod-20260218-163021/daylily-omics-analysis"
cd "$ADIR"

echo "=== Pulling fix ==="
git pull origin feat/modular-hybrid-workflows

echo "=== Deleting corrupt stage1 outputs for SR5x-ONT10x-17 ==="
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_hap.bam*
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/hybrid_stage1.bam*
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_hap.bed
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_hap.vcf
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_ins.fa
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_ins.bed

echo "=== Deleting corrupt stage1 outputs for SR20x-ONT10x-45 ==="
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_hap.bam*
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/hybrid_stage1.bam*
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_hap.bed
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_hap.vcf
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_ins.fa
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/stage1_ins.bed

echo "=== Deleting any stage2 outputs from corrupt stage1 ==="
rm -fv results/day/hg38/HIOa-HG003-SR5x-ONT10x-17-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/hybrid_stage2*
rm -fv results/day/hg38/HIOa-HG003-SR20x-ONT10x-45-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp/hybrid_stage2*

echo "=== Cleanup complete ==="
echo "Ready to restart snakemake"

