#!/usr/bin/env bash
set -euo pipefail
BD="_analysis_data/agbt_benchmark_alignment_concordance_stats"
TSV="$BD/consolidated_concordance.tsv"

echo "=== 1. Total rows (expect 15976 = 15975 data + 1 header) ==="
wc -l "$TSV"

echo ""
echo "=== 2. Unique TestGroups ==="
awk -F'\t' 'NR>1{print $21}' "$TSV" | sort -u

echo ""
echo "=== 3. Unique callers ==="
awk -F'\t' 'NR>1{print $20}' "$TSV" | sort -u

echo ""
echo "=== 4. dark_horses2 oct rows (expect 648) ==="
awk -F'\t' '$21=="dark_horses2" && $20=="oct"' "$TSV" | wc -l

echo ""
echo "=== 5. dark_horses2 clair3 rows (expect 648) ==="
awk -F'\t' '$21=="dark_horses2" && $20=="clair3"' "$TSV" | wc -l

echo ""
echo "=== 6. ilmn_all_downsamples_a clair3 rows (expect 0 — excluded) ==="
awk -F'\t' '$21=="ilmn_all_downsamples_a" && $20=="clair3"' "$TSV" | wc -l

echo ""
echo "=== 7. huo_old rows (expect 1134) ==="
awk -F'\t' '$21=="huo_old"' "$TSV" | wc -l

echo ""
echo "=== 8. huo_old caller+platform check ==="
awk -F'\t' '$21=="huo_old"{print $20, $22, $23}' "$TSV" | sort -u

echo ""
echo "=== 9. roche_ds_a rows (expect 567) ==="
awk -F'\t' '$21=="roche_ds_a"' "$TSV" | wc -l

echo ""
echo "=== 10. roche_ds_c rows (expect 216) ==="
awk -F'\t' '$21=="roche_ds_c"' "$TSV" | wc -l

echo ""
echo "=== 11. roche_ds_c fractional coverage check ==="
awk -F'\t' '$21=="roche_ds_c"{print $3, $24}' "$TSV" | sort -u

echo ""
echo "=== 12. Heatmap SVG count ==="
find "$BD"/heatmaps_fscore_* -name '*.svg' | wc -l
echo "Cost heatmap:"
ls -la "$BD/heatmaps_cost/cost_pipeline.svg" 2>/dev/null && echo "  exists" || echo "  MISSING"

echo ""
echo "=== 13. No empty VariantClass or ROI ==="
echo "Empty VariantClass:"
awk -F'\t' 'NR>1 && $2==""' "$TSV" | wc -l
echo "Empty ROI:"
awk -F'\t' 'NR>1 && $16==""' "$TSV" | wc -l

echo ""
echo "=== VERIFY DONE ==="

