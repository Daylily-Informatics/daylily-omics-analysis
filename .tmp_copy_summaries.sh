#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no $HEADNODE"
SCP="scp -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
RB="/fsx/analysis_results/ubuntu/hiomr_fullgenome_3x3x_15x15x_20260222/daylily-omics-analysis/results/day/hg38_broad"
LOCAL="./sentdhiomr_results"

S3x="HIOa-HG003-SR3x-ONT3x-8-D0-PF-ILMN-NOVASEQ"
S15x="HIOa-HG003-SR15x-ONT15x-39-D0-PF-ILMN-NOVASEQ"

# Clean previous partial copy
rm -rf "$LOCAL"
mkdir -p "$LOCAL/other_reports" "$LOCAL/SR3x-ONT3x" "$LOCAL/SR15x-ONT15x"

echo "=== 1. other_reports (alignstats) ==="
$SCP ${HEADNODE}:${RB}/other_reports/*.tsv "$LOCAL/other_reports/" 2>&1

echo "=== 2. SR3x-ONT3x concordance summaries ==="
for roi in giabHC giabHC_x_ultima giabHC_x_clinvar_genes giabHC_x_ultima_x_clinvar ultima clinvar_genes hg38 hg38_m_giabHC; do
  dir="${RB}/${S3x}/align/ont/na/snv/sentdhiomr/concordance/${roi}"
  $SSH "test -f ${dir}/summary.txt" 2>/dev/null && {
    mkdir -p "$LOCAL/SR3x-ONT3x/concordance/${roi}"
    $SCP ${HEADNODE}:${dir}/summary.txt "$LOCAL/SR3x-ONT3x/concordance/${roi}/" 2>&1
    $SCP ${HEADNODE}:${dir}/vcfeval_summary.parsed.tsv "$LOCAL/SR3x-ONT3x/concordance/${roi}/" 2>&1 || true
  } || echo "  skip ${roi} (not found)"
done

echo "=== 3. SR3x-ONT3x concordance .mqc.tsv ==="
$SCP ${HEADNODE}:"${RB}/${S3x}/align/ont/na/snv/sentdhiomr/concordance/*.mqc.tsv" "$LOCAL/SR3x-ONT3x/" 2>&1 || echo "  (none)"

echo "=== 4. SR15x-ONT15x concordance summaries ==="
for roi in giabHC giabHC_x_ultima giabHC_x_clinvar_genes giabHC_x_ultima_x_clinvar ultima clinvar_genes hg38 hg38_m_giabHC; do
  dir="${RB}/${S15x}/align/ont/na/snv/sentdhiomr/concordance/${roi}"
  $SSH "test -f ${dir}/summary.txt" 2>/dev/null && {
    mkdir -p "$LOCAL/SR15x-ONT15x/concordance/${roi}"
    $SCP ${HEADNODE}:${dir}/summary.txt "$LOCAL/SR15x-ONT15x/concordance/${roi}/" 2>&1
    $SCP ${HEADNODE}:${dir}/vcfeval_summary.parsed.tsv "$LOCAL/SR15x-ONT15x/concordance/${roi}/" 2>&1 || true
  } || echo "  skip ${roi} (not found)"
done

echo "=== 5. SR15x-ONT15x concordance .mqc.tsv ==="
$SCP ${HEADNODE}:"${RB}/${S15x}/align/ont/na/snv/sentdhiomr/concordance/*.mqc.tsv" "$LOCAL/SR15x-ONT15x/" 2>&1 || echo "  (none)"

echo "=== 6. Alignstats per sample ==="
for s in "$S3x" "$S15x"; do
  short=$(echo "$s" | grep -oP 'SR\dx-ONT\d+x' || echo "$s")
  mkdir -p "$LOCAL/${short}/alignstats"
  $SCP ${HEADNODE}:"${RB}/${s}/align/ont/na/alignqc/alignstats/*.tsv" "$LOCAL/${short}/alignstats/" 2>&1 || echo "  (none for $short)"
done

echo ""
echo "=== DONE ==="
find "$LOCAL" -type f | wc -l | xargs -I{} echo "Total files: {}"
du -sh "$LOCAL"

