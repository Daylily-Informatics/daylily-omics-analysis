#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pangenome_sr_dryrun_20260221/daylily-omics-analysis"
MANIFEST_DIR="${ANALYSIS_DIR}/.test_data/data"

echo "=== Creating HG003-only 30x manifests ==="

# samples.tsv: header + HG003 row
head -1 "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.samples.tsv" > "${MANIFEST_DIR}/hg003_30x_hg38.samples.tsv"
grep "^HG003" "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.samples.tsv" >> "${MANIFEST_DIR}/hg003_30x_hg38.samples.tsv"

# units.tsv: header + HG003 row
head -1 "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.units.tsv" > "${MANIFEST_DIR}/hg003_30x_hg38.units.tsv"
grep "HG003" "${MANIFEST_DIR}/giab_30x_hg38_analysis_manifest.units.tsv" >> "${MANIFEST_DIR}/hg003_30x_hg38.units.tsv"

echo "=== Samples ==="
cat "${MANIFEST_DIR}/hg003_30x_hg38.samples.tsv"
echo ""
echo "=== Units ==="
cat "${MANIFEST_DIR}/hg003_30x_hg38.units.tsv"
echo ""
echo "=== Done ==="

