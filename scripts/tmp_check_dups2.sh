#!/usr/bin/env bash
set -euo pipefail
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats/src_data
TAB="$(printf '\t')"

echo "=== pangenome_A vs pangenome_3_and_30x: R30x-HG003 SNPts giabHC Fscore ==="
echo "pangenome_A:"
awk -F"$TAB" 'NR>1 && $3 ~ /R30x-HG003/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/pangenome_A/giab_concordance_mqc.tsv"
echo "pangenome_B:"
awk -F"$TAB" 'NR>1 && $3 ~ /R30x-HG003/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/pangenome_B/giab_concordance_mqc.tsv"
echo "pangenome_3_and_30x:"
awk -F"$TAB" 'NR>1 && $3 ~ /R30x-HG003/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/pangenome_3_and_30x/giab_concordance_mqc.tsv"

echo ""
echo "=== pangenome_3_and_30x ROIs ==="
awk -F"$TAB" 'NR>1{print $16}' "$BD/pangenome_3_and_30x/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== ilmn_fin_pan2 vs ilmn_fin_pan: I2-HG003-40x SNPts giabHC Fscore ==="
echo "ilmn_fin_pan2:"
awk -F"$TAB" 'NR>1 && $3 ~ /I2-HG003-40x/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/ilmn_fin_pan2/giab_concordance_mqc.tsv"
echo "ilmn_fin_pan:"
awk -F"$TAB" 'NR>1 && $3 ~ /I2-HG003-40x/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/ilmn_fin_pan/giab_concordance_mqc.tsv"

echo ""
echo "=== hiomr_three vs hiomr_four: SR15x-ONT15x SNPts giabHC Fscore ==="
echo "hiomr_three:"
awk -F"$TAB" 'NR>1 && $3 ~ /SR15x-ONT15x/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/hiomr_three/giab_concordance_mqc.tsv"
echo "hiomr_four:"
awk -F"$TAB" 'NR>1 && $3 ~ /SR15x-ONT15x/ && $2=="SNPts" && $16=="giabHC"{print $9}' "$BD/hiomr_four/giab_concordance_mqc.tsv"

echo ""
echo "=== pangenome_A row count by ROI ==="
awk -F"$TAB" 'NR>1{print $16}' "$BD/pangenome_A/giab_concordance_mqc.tsv" | sort | uniq -c | sort -rn

echo ""
echo "=== pangenome_3_and_30x row count by ROI ==="
awk -F"$TAB" 'NR>1{print $16}' "$BD/pangenome_3_and_30x/giab_concordance_mqc.tsv" | sort | uniq -c | sort -rn

