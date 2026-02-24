#!/usr/bin/env bash
set -euo pipefail

# Create 3 analysis dirs for testing refactored hybrid pipelines
# Each uses day-clone to get a fresh clone of the feature branch

echo "=== Creating test-sentdhipmr-3x ==="
day-clone -t feat/modular-hybrid-workflows -w ssh -d test-sentdhipmr-3x
echo ""

echo "=== Creating test-sentdhuomr-3x ==="
day-clone -t feat/modular-hybrid-workflows -w ssh -d test-sentdhuomr-3x
echo ""

echo "=== Creating test-sentdhupmr-3x ==="
day-clone -t feat/modular-hybrid-workflows -w ssh -d test-sentdhupmr-3x
echo ""

echo "=== All 3 analysis dirs created ==="
ls -d /fsx/analysis_results/ubuntu/test-sent*-3x/daylily-omics-analysis/

