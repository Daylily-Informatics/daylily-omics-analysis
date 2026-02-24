#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_NAME="test-sentdhuomr-3units-small"

echo "=== Cloning repo ==="
source ~/.bashrc
day-clone -t feat/modular-hybrid-workflows -w ssh -d "$ANALYSIS_NAME"

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/${ANALYSIS_NAME}/daylily-omics-analysis"
echo "=== Analysis dir: $ANALYSIS_DIR ==="

echo "=== Copying units.tsv and samples.tsv ==="
cp /tmp/huomr_units.tsv "$ANALYSIS_DIR/config/units.tsv"
cp /tmp/huomr_samples.tsv "$ANALYSIS_DIR/config/samples.tsv"

echo "=== Verifying ==="
echo "units.tsv lines: $(wc -l < "$ANALYSIS_DIR/config/units.tsv")"
echo "samples.tsv lines: $(wc -l < "$ANALYSIS_DIR/config/samples.tsv")"
cat "$ANALYSIS_DIR/config/units.tsv"
echo ""
cat "$ANALYSIS_DIR/config/samples.tsv"

echo ""
echo "=== Setup complete ==="
echo "Analysis dir: $ANALYSIS_DIR"

