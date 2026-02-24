#!/usr/bin/env bash
set -euo pipefail
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats/src_data
TAB="$(printf '\t')"

echo "=== RLEN samples ==="
awk -F"$TAB" 'NR>1{print $3}' "$BD/RLEN/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== ilmn_read_trim samples (first 5) ==="
awk -F"$TAB" 'NR>1{print $3}' "$BD/ilmn_read_trim/giab_concordance_mqc.tsv" | sort -u | head -5

echo ""
echo "=== read_len: On1c-HG003-100x in ont_dv19? ==="
awk -F"$TAB" 'NR>1 && $3 ~ /On1c-HG003-100x/{print $3}' "$BD/ont_dv19/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== pangenome_A samples ==="
awk -F"$TAB" 'NR>1{print $3}' "$BD/pangenome_A/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== pangenome_3_and_30x samples ==="
awk -F"$TAB" 'NR>1{print $3}' "$BD/pangenome_3_and_30x/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== ilmn_fin_pan2 ROIs ==="
awk -F"$TAB" 'NR>1{print $16}' "$BD/ilmn_fin_pan2/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== ilmn_fin_pan ROIs ==="
awk -F"$TAB" 'NR>1{print $16}' "$BD/ilmn_fin_pan/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== hiomr_three vs hiomr_one/two samples ==="
echo "hiomr_three:"
awk -F"$TAB" 'NR>1{print $3}' "$BD/hiomr_three/giab_concordance_mqc.tsv" | sort -u
echo "hiomr_four:"
awk -F"$TAB" 'NR>1{print $3}' "$BD/hiomr_four/giab_concordance_mqc.tsv" | sort -u
echo "hiomr_one:"
awk -F"$TAB" 'NR>1{print $3}' "$BD/hiomr_one/giab_concordance_mqc.tsv" | sort -u
echo "hiomr_two:"
awk -F"$TAB" 'NR>1{print $3}' "$BD/hiomr_two/giab_concordance_mqc.tsv" | sort -u

