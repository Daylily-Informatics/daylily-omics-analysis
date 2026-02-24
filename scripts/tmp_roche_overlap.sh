#!/usr/bin/env bash
set -euo pipefail
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

echo "=== roche_ds_a samples ==="
awk -F'\t' 'NR>1{print $3}' "$BD/roche_ds_a/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== roche_ds_b samples ==="
awk -F'\t' 'NR>1{print $3}' "$BD/roche_ds_b/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== roche_ds_c samples ==="
awk -F'\t' 'NR>1{print $3}' "$BD/roche_ds_c/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== roche_ds_b in roche_ds_c? ==="
comm -23 \
  <(awk -F'\t' 'NR>1{print $1}' "$BD/roche_ds_b/giab_concordance_mqc.tsv" | sort) \
  <(awk -F'\t' 'NR>1{print $1}' "$BD/roche_ds_c/giab_concordance_mqc.tsv" | sort) | wc -l | tr -d ' '
echo "  (0 means b is a subset of c)"

echo ""
echo "=== huo_old samples ==="
awk -F'\t' 'NR>1{print $3}' "$BD/huo_old/giab_concordance_mqc.tsv" | sort -u

echo ""
echo "=== dark_horses2: callers x samples x footprints (giabHC+All only) ==="
awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="SNPClass")s=i;if($i=="CmpFootprint")f=i;if($i=="SNVCaller")c=i;if($i=="Sample")sa=i}} NR>1 && $s=="All" && $f=="giabHC"{print $c"\t"$sa}' "$BD/dark_horses2/giab_concordance_mqc.tsv" | sort

echo ""
echo "=== DONE ==="

