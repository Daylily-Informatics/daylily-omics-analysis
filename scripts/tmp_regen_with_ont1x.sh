#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

BD=_analysis_data/agbt_benchmark_alignment_concordance_stats
PY=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3

echo "=== STEP 1: Regenerate consolidated TSV ==="
$PY "$BD/consolidate_concordance.py" 2>&1

echo ""
echo "=== Verify ONT 1x rows now have non-zero secondary coverage ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="TestGroup") tg=i
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
        if($i=="Sample") sa=i
        if($i=="Secondary_Tgt_Cov") stc=i
        if($i=="Secondary_MeasuredMeanCov") smc=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" && ($tg=="hio_cli" || $tg=="hio_fillin") && $stc=="1" {
    printf "%s\tONTtgt=%sx\tONTmeas=%s\t%s\n", $tg, $stc, $smc, $sa
}
' "$BD/consolidated_concordance.tsv"

echo ""
echo "=== STEP 2: Regenerate heatmaps ==="
for fp in hg38 giabHC clinvar_genes hg38_m_giabHC ultima giabHC_x_ultima giabHC_x_clinvar_genes giabHC_x_ultima_x_clinvar; do
    echo "  Generating: $fp"
    $PY "$BD/heatmap_fscore_hg38.py" "$fp" 2>&1 | grep -E "^Done|HIO columns" || echo "  (no match for $fp)"
done

echo ""
echo "=== STEP 3: Regenerate cost heatmap ==="
$PY "$BD/heatmap_cost.py" 2>&1 | tail -3

echo ""
echo "=== ALL DONE ==="

