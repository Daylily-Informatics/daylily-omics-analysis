#!/usr/bin/env bash
set -euo pipefail
BD=/Users/jmajor/projects/daylily/daylily-omics-analysis/_analysis_data/agbt_benchmark_alignment_concordance_stats

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
    echo "  Sample examples: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | head -5 | tr '\n' ', ' | sed 's/,$//')"
    echo ""
}

echo "============================================="
echo "DIRECTORIES NOT IN CONSOLIDATION SCRIPT"
echo "============================================="
echo ""
for d in dark_horses2 hiom_jem huo_old roche_ds_a roche_ds_b roche_ds_c; do
    detail "$d"
done

echo "============================================="
echo "DIRECTORIES IN SCRIPT (for reference)"
echo "============================================="
echo ""
for d in hio_cli hio_fillin hio_old ilmn_all_downsamples_a ilmn_hg003_ilmn_sentonly ilmn_read_trim pacbio_ds ultima_ds ont_dv19 ilmn_gatk_b dragen_fullold; do
    detail "$d"
done

echo ""
echo "=== ont_ds (special path: ont_ds/ont_patch/) ==="
f="$BD/ont_ds/ont_patch/giab_concordance_mqc.tsv"
echo "  Data rows: $(awk 'END{print NR-1}' "$f")"
echo "  Unique samples: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | wc -l | tr -d ' ')"
colnames=$(head -1 "$f" | tr '\t' '\n')
caller_col=$(echo "$colnames" | grep -n '^SNVCaller$\|^Caller$' | cut -d: -f1 | head -1)
aligner_col=$(echo "$colnames" | grep -n '^Aligner$' | cut -d: -f1 | head -1)
[ -n "$caller_col" ] && echo "  Callers: $(awk -F'\t' -v c="$caller_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
[ -n "$aligner_col" ] && echo "  Aligners: $(awk -F'\t' -v c="$aligner_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"

echo ""
echo "============================================="
echo "DIRECTORIES WITH NO giab_concordance_mqc.tsv"
echo "============================================="
for d in $(ls -1d "$BD"/*/ 2>/dev/null | sed "s|$BD/||" | sed 's|/||' | sort); do
    case "$d" in
        __pycache__|heatmaps_*) continue ;;
    esac
    if [ ! -f "$BD/$d/giab_concordance_mqc.tsv" ]; then
        # check subdirectories
        sub=$(find "$BD/$d" -name "giab_concordance_mqc.tsv" -type f 2>/dev/null | head -1)
        if [ -n "$sub" ]; then
            echo "  $d -> found at: $(echo "$sub" | sed "s|$BD/||")"
        else
            echo "  $d -> NO giab_concordance_mqc.tsv found"
            ls "$BD/$d/" 2>/dev/null | head -5 | sed "s/^/    /"
        fi
    fi
done

echo ""
echo "=== DUPLICATE CHECK: hiom_jem vs hio_fillin (quick md5) ==="
md5 -q "$BD/hiom_jem/giab_concordance_mqc.tsv" 2>/dev/null || md5sum "$BD/hiom_jem/giab_concordance_mqc.tsv" 2>/dev/null
md5 -q "$BD/hio_fillin/giab_concordance_mqc.tsv" 2>/dev/null || md5sum "$BD/hio_fillin/giab_concordance_mqc.tsv" 2>/dev/null

echo ""
echo "=== DONE ==="

