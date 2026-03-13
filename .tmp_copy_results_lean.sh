#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no $HEADNODE"
SCP="scp -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
REMOTE_BASE="/fsx/analysis_results/ubuntu/hiomr_fullgenome_3x3x_15x15x_20260222/daylily-omics-analysis/results/day/hg38_broad"
LOCAL="./sentdhiomr_results"

# Clean previous partial copy
rm -rf "$LOCAL"
mkdir -p "$LOCAL/other_reports"
mkdir -p "$LOCAL/SR3x-ONT3x/concordance_summaries"
mkdir -p "$LOCAL/SR15x-ONT15x/concordance_summaries"
mkdir -p "$LOCAL/SR3x-ONT3x/alignstats"
mkdir -p "$LOCAL/SR15x-ONT15x/alignstats"

S3x="HIOa-HG003-SR3x-ONT3x-8-D0-PF-ILMN-NOVASEQ"
S15x="HIOa-HG003-SR15x-ONT15x-39-D0-PF-ILMN-NOVASEQ"

echo "=== 1. other_reports (alignstats summaries) ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/other_reports/*.tsv "$LOCAL/other_reports/" 2>&1

echo "=== 2. SR3x concordance summaries only ==="
$SSH "find ${REMOTE_BASE}/${S3x}/align/ont/na/snv/sentdhiomr/concordance/ -maxdepth 2 \( -name '*.mqc.tsv' -o -name 'summary.txt' -o -name 'vcfeval_summary.parsed.tsv' -o -name '*.log' \) -type f" | while read -r f; do
    $SCP ${HEADNODE}:"$f" "$LOCAL/SR3x-ONT3x/concordance_summaries/" 2>&1
done

echo "=== 3. SR15x concordance summaries only ==="
$SSH "find ${REMOTE_BASE}/${S15x}/align/ont/na/snv/sentdhiomr/concordance/ -maxdepth 2 \( -name '*.mqc.tsv' -o -name 'summary.txt' -o -name 'vcfeval_summary.parsed.tsv' -o -name '*.log' \) -type f" | while read -r f; do
    $SCP ${HEADNODE}:"$f" "$LOCAL/SR15x-ONT15x/concordance_summaries/" 2>&1
done

echo "=== 4. SR3x alignstats ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/alignqc/alignstats/*.tsv "$LOCAL/SR3x-ONT3x/alignstats/" 2>&1 || echo "  (no tsv)"
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/alignqc/alignstats/*.txt "$LOCAL/SR3x-ONT3x/alignstats/" 2>&1 || echo "  (no txt)"

echo "=== 5. SR15x alignstats ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/alignqc/alignstats/*.tsv "$LOCAL/SR15x-ONT15x/alignstats/" 2>&1 || echo "  (no tsv)"
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/alignqc/alignstats/*.txt "$LOCAL/SR15x-ONT15x/alignstats/" 2>&1 || echo "  (no txt)"

echo ""
echo "=== DONE ==="
find "$LOCAL" -type f | wc -l | xargs -I{} echo "Total files: {}"
du -sh "$LOCAL"
echo "---"
find "$LOCAL" -type f | sort

