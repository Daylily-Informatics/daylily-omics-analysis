#!/usr/bin/env bash
set -euo pipefail
BD=/Users/jmajor/projects/daylily/daylily-omics-analysis/_analysis_data/agbt_benchmark_alignment_concordance_stats
OUT=/tmp/audit_results.txt

detail() {
    local dir="$1"
    local f="$BD/$dir/giab_concordance_mqc.tsv"
    if [ ! -f "$f" ]; then echo "  FILE NOT FOUND: $f"; return; fi
    local colnames
    colnames=$(head -1 "$f" | tr '\t' '\n')
    echo "--- $dir ---"
    echo "  Data rows: $(awk 'END{print NR-1}' "$f")"
    echo "  Unique samples: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | wc -l | tr -d ' ')"
    echo "  Columns: $(head -1 "$f" | awk -F'\t' '{print NF}')"
    local caller_col aligner_col fp_col sc_col
    caller_col=$(echo "$colnames" | grep -n '^SNVCaller$\|^Caller$' | cut -d: -f1 | head -1)
    aligner_col=$(echo "$colnames" | grep -n '^Aligner$' | cut -d: -f1 | head -1)
    fp_col=$(echo "$colnames" | grep -n '^CmpFootprint$' | cut -d: -f1 | head -1)
    sc_col=$(echo "$colnames" | grep -n '^SNPClass$\|^VariantClass$' | cut -d: -f1 | head -1)
    [ -n "$caller_col" ] && echo "  Callers: $(awk -F'\t' -v c="$caller_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    [ -n "$aligner_col" ] && echo "  Aligners: $(awk -F'\t' -v c="$aligner_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    [ -n "$fp_col" ] && echo "  Footprints: $(awk -F'\t' -v c="$fp_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    [ -n "$sc_col" ] && echo "  SNPClasses: $(awk -F'\t' -v c="$sc_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    echo "  Samples: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    echo ""
}

{
echo "===== NOT IN CONSOLIDATION SCRIPT ====="
echo ""
for d in dark_horses2 hiom_jem huo_old roche_ds_a roche_ds_b roche_ds_c; do
    detail "$d"
done

echo "===== IN CONSOLIDATION SCRIPT ====="
echo ""
for d in hio_cli hio_fillin hio_old ilmn_all_downsamples_a ilmn_hg003_ilmn_sentonly ilmn_read_trim pacbio_ds ultima_ds ont_dv19 ilmn_gatk_b dragen_fullold; do
    echo "--- $d --- rows:$(awk 'END{print NR-1}' "$BD/$d/giab_concordance_mqc.tsv") samples:$(awk -F'\t' 'NR>1{print $3}' "$BD/$d/giab_concordance_mqc.tsv" | sort -u | wc -l | tr -d ' ')"
done
echo "--- ont_ds/ont_patch --- rows:$(awk 'END{print NR-1}' "$BD/ont_ds/ont_patch/giab_concordance_mqc.tsv") samples:$(awk -F'\t' 'NR>1{print $3}' "$BD/ont_ds/ont_patch/giab_concordance_mqc.tsv" | sort -u | wc -l | tr -d ' ')"

echo ""
echo "===== DIRS WITH NO giab_concordance_mqc.tsv ====="
for d in dragen_old xxx; do
    echo "  $d: $(ls "$BD/$d/" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')"
done

echo ""
echo "===== MD5 CHECK: hiom_jem vs hio_fillin ====="
echo "hiom_jem: $(md5 -q "$BD/hiom_jem/giab_concordance_mqc.tsv")"
echo "hio_fillin: $(md5 -q "$BD/hio_fillin/giab_concordance_mqc.tsv")"
} > "$OUT" 2>&1

echo "Audit written to $OUT ($(wc -l < "$OUT") lines)"

