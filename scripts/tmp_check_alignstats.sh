#!/usr/bin/env bash
set -euo pipefail
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

for d in dark_horses2 huo_old roche_ds_a roche_ds_c; do
    echo "=== $d ==="
    if [ -f "$BD/$d/alignstats_combo_mqc.tsv" ]; then
        echo "  HAS alignstats_combo_mqc.tsv"
        wc -l "$BD/$d/alignstats_combo_mqc.tsv"
        head -2 "$BD/$d/alignstats_combo_mqc.tsv"
    else
        echo "  NO alignstats_combo_mqc.tsv"
        ls "$BD/$d/" | head -5
    fi
    echo ""
done

echo "=== dark_horses2 clair3 vs ilmn_all_downsamples_a clair3 overlap ==="
echo "dark_horses2 clair3 mqc_ids:"
awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="SNVCaller")c=i;if($i=="mqc_id")m=i}} NR>1 && $c=="clair3"{print $m}' "$BD/dark_horses2/giab_concordance_mqc.tsv" | sort > /tmp/dh2_clair3_ids.txt
wc -l /tmp/dh2_clair3_ids.txt

echo "ilmn_all_downsamples_a clair3 mqc_ids:"
awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="SNVCaller")c=i;if($i=="mqc_id")m=i}} NR>1 && $c=="clair3"{print $m}' "$BD/ilmn_all_downsamples_a/giab_concordance_mqc.tsv" | sort > /tmp/ilda_clair3_ids.txt
wc -l /tmp/ilda_clair3_ids.txt

echo "Common mqc_ids:"
comm -12 /tmp/dh2_clair3_ids.txt /tmp/ilda_clair3_ids.txt | wc -l

echo "Only in dark_horses2:"
comm -23 /tmp/dh2_clair3_ids.txt /tmp/ilda_clair3_ids.txt | wc -l

echo "Only in ilmn_all_downsamples_a:"
comm -13 /tmp/dh2_clair3_ids.txt /tmp/ilda_clair3_ids.txt | wc -l

echo ""
echo "=== ilmn_all_downsamples_a clair3 aligners ==="
awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="SNVCaller")c=i;if($i=="Aligner")a=i}} NR>1 && $c=="clair3"{print $a}' "$BD/ilmn_all_downsamples_a/giab_concordance_mqc.tsv" | sort | uniq -c

echo ""
echo "=== DONE ==="

