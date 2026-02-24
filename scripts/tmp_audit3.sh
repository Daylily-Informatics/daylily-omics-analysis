#!/usr/bin/env bash
set -euo pipefail
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats
OUT=scripts/tmp_audit_output.txt
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

detail() {
    local f="$1"
    local colnames
    colnames=$(head -1 "$f" | tr '\t' '\n')
    echo "  rows:$(awk 'END{print NR-1}' "$f") samples:$(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | wc -l | tr -d ' ') cols:$(head -1 "$f" | awk -F'\t' '{print NF}')"
    local cc ac fc sc
    cc=$(echo "$colnames" | grep -n '^SNVCaller$\|^Caller$' | cut -d: -f1 | head -1)
    ac=$(echo "$colnames" | grep -n '^Aligner$' | cut -d: -f1 | head -1)
    fc=$(echo "$colnames" | grep -n '^CmpFootprint$' | cut -d: -f1 | head -1)
    sc=$(echo "$colnames" | grep -n '^SNPClass$\|^VariantClass$' | cut -d: -f1 | head -1)
    [ -n "$cc" ] && echo "  callers: $(awk -F'\t' -v c="$cc" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ',' | sed 's/,$//')"
    [ -n "$ac" ] && echo "  aligners: $(awk -F'\t' -v c="$ac" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ',' | sed 's/,$//')"
    [ -n "$fc" ] && echo "  footprints: $(awk -F'\t' -v c="$fc" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ',' | sed 's/,$//')"
    [ -n "$sc" ] && echo "  classes: $(awk -F'\t' -v c="$sc" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ',' | sed 's/,$//')"
    echo "  sample_ex: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | head -3 | tr '\n' ',' | sed 's/,$//')"
}

exec > "$OUT" 2>&1
echo "=== NOT IN CONSOLIDATION SCRIPT ==="
for d in dark_horses2 hiom_jem huo_old roche_ds_a roche_ds_b roche_ds_c; do
    echo "[$d]"
    detail "$BD/$d/giab_concordance_mqc.tsv"
    echo ""
done

echo "=== IN CONSOLIDATION SCRIPT ==="
for d in hio_cli hio_fillin hio_old ilmn_all_downsamples_a ilmn_hg003_ilmn_sentonly ilmn_read_trim pacbio_ds ultima_ds ont_dv19 ilmn_gatk_b dragen_fullold; do
    echo "[$d]"
    detail "$BD/$d/giab_concordance_mqc.tsv"
    echo ""
done
echo "[ont_ds/ont_patch]"
detail "$BD/ont_ds/ont_patch/giab_concordance_mqc.tsv"
echo ""

echo "=== NO giab_concordance FILE ==="
echo "dragen_old: $(ls "$BD/dragen_old/" | tr '\n' ',')"
echo "xxx: $(ls "$BD/xxx/" 2>/dev/null | tr '\n' ',')" || true

echo ""
echo "=== MD5 ==="
echo "hiom_jem: $(md5 -q "$BD/hiom_jem/giab_concordance_mqc.tsv")"
echo "hio_fillin: $(md5 -q "$BD/hio_fillin/giab_concordance_mqc.tsv")"

echo ""
echo "AUDIT_COMPLETE"

