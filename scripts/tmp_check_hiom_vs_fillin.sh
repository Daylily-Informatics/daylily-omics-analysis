#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats

echo "=== LINE COUNTS ==="
wc -l "$BD/hiom_jem/giab_concordance_mqc.tsv" "$BD/hio_fillin/giab_concordance_mqc.tsv"

echo ""
echo "=== DIFF (first 20 differences) ==="
diff "$BD/hiom_jem/giab_concordance_mqc.tsv" "$BD/hio_fillin/giab_concordance_mqc.tsv" | head -40 || true

echo ""
echo "=== hiom_jem samples NOT in hio_fillin ==="
comm -23 \
  <(awk -F'\t' 'NR>1{print $3}' "$BD/hiom_jem/giab_concordance_mqc.tsv" | sort -u) \
  <(awk -F'\t' 'NR>1{print $3}' "$BD/hio_fillin/giab_concordance_mqc.tsv" | sort -u)

echo ""
echo "=== hio_fillin samples NOT in hiom_jem ==="
comm -13 \
  <(awk -F'\t' 'NR>1{print $3}' "$BD/hiom_jem/giab_concordance_mqc.tsv" | sort -u) \
  <(awk -F'\t' 'NR>1{print $3}' "$BD/hio_fillin/giab_concordance_mqc.tsv" | sort -u)

echo ""
echo "=== hiom_jem: giabHC + All rows with ONT coverage info ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
        if($i=="Sample") sa=i
        if($i=="Fscore") fs=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" {
    print $sa "\t" $fs
}
' "$BD/hiom_jem/giab_concordance_mqc.tsv" | sort

echo ""
echo "=== hio_fillin: giabHC + All rows ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
        if($i=="Sample") sa=i
        if($i=="Fscore") fs=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" {
    print $sa "\t" $fs
}
' "$BD/hio_fillin/giab_concordance_mqc.tsv" | sort

echo ""
echo "=== WHY FEWER ON HEATMAP: HIO rows with 0.0 secondary measured coverage ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="TestGroup") tg=i
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
        if($i=="Sample") sa=i
        if($i=="Secondary_MeasuredMeanCov") smc=i
        if($i=="Secondary_Tgt_Cov") stc=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" && ($tg=="hio_cli" || $tg=="hio_fillin" || $tg=="hio_old") {
    smcv = ($smc=="" || $smc==" ") ? "EMPTY" : $smc
    printf "%s\tONTtgt=%sx\tONTmeas=%s\t%s\n", $tg, $stc, smcv, $sa
}
' "$BD/consolidated_concordance.tsv" | sort -t$'\t' -k3,3

echo ""
echo "=== DONE ==="

