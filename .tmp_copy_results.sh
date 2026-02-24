#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SCP="scp -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no -r"
REMOTE_BASE="/fsx/analysis_results/ubuntu/hiomr_fullgenome_3x3x_15x15x_20260222/daylily-omics-analysis/results/day/hg38_broad"
LOCAL="./sentdhiomr_results"

mkdir -p "$LOCAL/other_reports"
mkdir -p "$LOCAL/reports"
mkdir -p "$LOCAL/SR3x-ONT3x/concordance"
mkdir -p "$LOCAL/SR15x-ONT15x/concordance"
mkdir -p "$LOCAL/SR3x-ONT3x/alignstats"
mkdir -p "$LOCAL/SR15x-ONT15x/alignstats"
mkdir -p "$LOCAL/SR3x-ONT3x/vcfs"
mkdir -p "$LOCAL/SR15x-ONT15x/vcfs"
mkdir -p "$LOCAL/SR3x-ONT3x/benchmarks"
mkdir -p "$LOCAL/SR15x-ONT15x/benchmarks"
mkdir -p "$LOCAL/SR3x-ONT3x/logs"
mkdir -p "$LOCAL/SR15x-ONT15x/logs"

S3x="HIOa-HG003-SR3x-ONT3x-8-D0-PF-ILMN-NOVASEQ"
S15x="HIOa-HG003-SR15x-ONT15x-39-D0-PF-ILMN-NOVASEQ"

echo "=== Copying other_reports ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/other_reports/* "$LOCAL/other_reports/" 2>&1 || echo "  (some files may not exist)"

echo "=== Copying reports ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/reports/* "$LOCAL/reports/" 2>&1 || echo "  (some files may not exist)"

echo "=== Copying SR3x-ONT3x concordance ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/snv/sentdhiomr/concordance/ "$LOCAL/SR3x-ONT3x/concordance/" 2>&1 || echo "  (partial)"

echo "=== Copying SR15x-ONT15x concordance ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/snv/sentdhiomr/concordance/ "$LOCAL/SR15x-ONT15x/concordance/" 2>&1 || echo "  (partial)"

echo "=== Copying SR3x-ONT3x alignstats ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/alignqc/alignstats/ "$LOCAL/SR3x-ONT3x/alignstats/" 2>&1 || echo "  (partial)"

echo "=== Copying SR15x-ONT15x alignstats ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/alignqc/alignstats/ "$LOCAL/SR15x-ONT15x/alignstats/" 2>&1 || echo "  (partial)"

echo "=== Copying SR3x-ONT3x final VCF ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/snv/sentdhiomr/${S3x}.ont.na.sentdhiomr.snv.sort.vcf.gz* "$LOCAL/SR3x-ONT3x/vcfs/" 2>&1 || echo "  (partial)"

echo "=== Copying SR15x-ONT15x final VCF ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/snv/sentdhiomr/${S15x}.ont.na.sentdhiomr.snv.sort.vcf.gz* "$LOCAL/SR15x-ONT15x/vcfs/" 2>&1 || echo "  (partial)"

echo "=== Copying SR3x-ONT3x benchmarks ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/snv/sentdhiomr/bench/ "$LOCAL/SR3x-ONT3x/benchmarks/" 2>&1 || echo "  (no benchmarks)"

echo "=== Copying SR15x-ONT15x benchmarks ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/snv/sentdhiomr/bench/ "$LOCAL/SR15x-ONT15x/benchmarks/" 2>&1 || echo "  (no benchmarks)"

echo "=== Copying SR3x-ONT3x logs ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S3x}/align/ont/na/snv/sentdhiomr/log/ "$LOCAL/SR3x-ONT3x/logs/" 2>&1 || echo "  (partial)"

echo "=== Copying SR15x-ONT15x logs ==="
$SCP ${HEADNODE}:${REMOTE_BASE}/${S15x}/align/ont/na/snv/sentdhiomr/log/ "$LOCAL/SR15x-ONT15x/logs/" 2>&1 || echo "  (partial)"

echo ""
echo "=== DONE ==="
echo "Results copied to: $LOCAL"
find "$LOCAL" -type f | wc -l | xargs -I{} echo "Total files: {}"

