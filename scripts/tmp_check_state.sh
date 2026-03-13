#!/bin/bash
set -e
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats

echo "=== CONSOLIDATED LINE COUNT ==="
wc -l "$BD/consolidated_concordance.tsv"

echo ""
echo "=== TEST GROUPS IN CONSOLIDATED ==="
awk -F'\t' 'NR==1{for(i=1;i<=NF;i++) if($i=="TestGroup") tg=i} NR>1{print $tg}' "$BD/consolidated_concordance.tsv" | sort | uniq -c | sort -rn

echo ""
echo "=== MISSING DIRS REFERENCED BY SCRIPT ==="
for d in roche_ds roche_ds_fillinone; do
    if [ -d "$BD/$d" ]; then
        echo "EXISTS: $BD/$d"
    else
        echo "MISSING: $BD/$d"
    fi
done

echo ""
echo "=== EXTRA DIRS NOT IN SCRIPT ==="
for d in dark_horses huo_old hiom_jem roche_ds_a roche_ds_b roche_ds_c; do
    if [ -d "$BD/$d" ]; then
        echo "EXISTS (not in script): $BD/$d  lines=$(wc -l < "$BD/$d/giab_concordance_mqc.tsv" 2>/dev/null || echo 'N/A')"
    fi
done

echo ""
echo "=== HIO DATA IN CONSOLIDATED ==="
awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="TestGroup") tg=i; if($i=="VariantClass") sc=i; if($i=="ROI") cf=i}} NR>1 && $sc=="All" && $cf=="giabHC" && ($tg=="hio_cli" || $tg=="hio_fillin" || $tg=="hio_old"){print $tg}' "$BD/consolidated_concordance.tsv" | sort | uniq -c

echo ""
echo "DONE"

