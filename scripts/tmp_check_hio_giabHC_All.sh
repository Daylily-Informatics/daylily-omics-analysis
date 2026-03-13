#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats
PY=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3

echo "=== HIO rows in consolidated where ROI=giabHC AND VariantClass=All ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="TestGroup") tg=i
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
        if($i=="Sample") sa=i
        if($i=="Fscore") fs=i
        if($i=="Primary_Tgt_Cov") ptc=i
        if($i=="Secondary_Tgt_Cov") stc=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" && ($tg=="hio_cli" || $tg=="hio_fillin" || $tg=="hio_old") {
    print $tg "\t" $sa "\tSR" $ptc "x-ONT" $stc "x\tFscore=" $fs
}
' "$BD/consolidated_concordance.tsv" | sort -t$'\t' -k1,1 -k3,3

echo ""
echo "=== COUNT per TestGroup ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="TestGroup") tg=i
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" && ($tg=="hio_cli" || $tg=="hio_fillin" || $tg=="hio_old") {
    print $tg
}
' "$BD/consolidated_concordance.tsv" | sort | uniq -c

echo ""
echo "=== DUPLICATE CHECK: same Sample+ROI+VariantClass across hio_cli vs hio_fillin ==="
awk -F'\t' '
NR==1 {
    for(i=1;i<=NF;i++) {
        if($i=="TestGroup") tg=i
        if($i=="VariantClass") sc=i
        if($i=="ROI") cf=i
        if($i=="Sample") sa=i
        if($i=="mqc_id") mid=i
    }
}
NR>1 && $sc=="All" && $cf=="giabHC" && ($tg=="hio_cli" || $tg=="hio_fillin" || $tg=="hio_old") {
    key = $sa "|" $cf "|" $sc
    tgs[key] = tgs[key] "," $tg
    count[key]++
}
END {
    for (k in count) {
        if (count[k] > 1) print "DUP(" count[k] "): " k " -> " tgs[k]
    }
}
' "$BD/consolidated_concordance.tsv" | sort

echo ""
echo "=== What does heatmap script actually plot for HIO? ==="
echo "(checking how heatmap builds HIO columns)"
grep -n "HIO\|hio_cli\|hio_fillin\|hio_old\|Secondary_Tgt_Cov\|ONT.*col" "$BD/heatmap_fscore_hg38.py" | head -30

echo ""
echo "=== DONE ==="

