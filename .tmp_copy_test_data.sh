#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== sentdhipmr (ILMN+PB) ==="
D="$BASE/test-sentdhipmr-3x/daylily-omics-analysis"
cp "$D/.test_data/data/hybrid/ilmn_pb/hg003/3x/samples.tsv" "$D/config/samples.tsv"
cp "$D/.test_data/data/hybrid/ilmn_pb/hg003/3x/units.tsv" "$D/config/units.tsv"
echo "  samples: $(wc -l < "$D/config/samples.tsv") lines"
echo "  units:   $(wc -l < "$D/config/units.tsv") lines"

echo ""
echo "=== sentdhuomr (UG+ONT) ==="
D="$BASE/test-sentdhuomr-3x/daylily-omics-analysis"
cp "$D/.test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv" "$D/config/samples.tsv"
cp "$D/.test_data/data/hybrid/ug_ont/hg003/3x/units.tsv" "$D/config/units.tsv"
echo "  samples: $(wc -l < "$D/config/samples.tsv") lines"
echo "  units:   $(wc -l < "$D/config/units.tsv") lines"

echo ""
echo "=== sentdhupmr (UG+PB) ==="
D="$BASE/test-sentdhupmr-3x/daylily-omics-analysis"
cp "$D/.test_data/data/hybrid/ug_pb/hg003/3x/samples.tsv" "$D/config/samples.tsv"
cp "$D/.test_data/data/hybrid/ug_pb/hg003/3x/units.tsv" "$D/config/units.tsv"
echo "  samples: $(wc -l < "$D/config/samples.tsv") lines"
echo "  units:   $(wc -l < "$D/config/units.tsv") lines"

echo ""
echo "=== Done ==="

