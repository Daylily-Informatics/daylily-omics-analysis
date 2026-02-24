#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pangenome_sr_dryrun_20260221/daylily-omics-analysis"
MANIFEST_DIR="${ANALYSIS_DIR}/.test_data/data"

echo "=== Creating HG002-only 30x manifests ==="

head -1 "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.samples.tsv" > "${MANIFEST_DIR}/hg002_30x_hg38.samples.tsv"
grep "^HG002" "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.samples.tsv" >> "${MANIFEST_DIR}/hg002_30x_hg38.samples.tsv"

head -1 "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.units.tsv" > "${MANIFEST_DIR}/hg002_30x_hg38.units.tsv"
grep "HG002" "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.units.tsv" >> "${MANIFEST_DIR}/hg002_30x_hg38.units.tsv"

echo "=== Created manifests ==="
echo "Samples:"
cat "${MANIFEST_DIR}/hg002_30x_hg38.samples.tsv"
echo ""
echo "Units:"
cat "${MANIFEST_DIR}/hg002_30x_hg38.units.tsv"
echo "=== Done ==="
