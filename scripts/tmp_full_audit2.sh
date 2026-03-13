#!/usr/bin/env bash
set -euo pipefail
BD=/Users/jmajor/projects/daylily/daylily-omics-analysis/_analysis_data/agbt_benchmark_alignment_concordance_stats

echo "=== TEST_GROUPS referenced in consolidation script ==="
# Extract test group names from the TEST_GROUPS list in the script
awk '/^TEST_GROUPS/,/^\]/' "$BD/consolidate_concordance.py" | grep -o '"[^"]*"' | head -50
echo ""

echo "=== ont_ds subdirectory check ==="
find "$BD/ont_ds" -name "giab_concordance_mqc.tsv" -type f 2>/dev/null
echo ""

echo "=== dragen_old directory check ==="
ls -la "$BD/dragen_old/" 2>/dev/null || echo "dragen_old dir not found or empty"
echo ""

echo "=== Per-directory detail for ALL giab_concordance_mqc.tsv files ==="
find "$BD" -maxdepth 2 -name "giab_concordance_mqc.tsv" -type f 2>/dev/null | sort | while read -r f; do
    dir=$(dirname "$f" | sed "s|$BD/||")
    echo "--- $dir ---"
    ncols=$(head -1 "$f" | awk -F'\t' '{print NF}')
    echo "  Columns: $ncols"
    nrows=$(awk 'END{print NR-1}' "$f")
    echo "  Data rows: $nrows"
    nsamples=$(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | wc -l | tr -d ' ')
    echo "  Unique samples: $nsamples"
    # Get column names
    colnames=$(head -1 "$f" | tr '\t' '\n')
    # Callers
    caller_col=$(echo "$colnames" | grep -n '^SNVCaller$\|^Caller$' | cut -d: -f1 | head -1)
    if [ -n "$caller_col" ]; then
        echo "  Callers: $(awk -F'\t' -v c="$caller_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    else
        echo "  Callers: (no SNVCaller/Caller column)"
    fi
    # Aligners
    aligner_col=$(echo "$colnames" | grep -n '^Aligner$' | cut -d: -f1 | head -1)
    if [ -n "$aligner_col" ]; then
        echo "  Aligners: $(awk -F'\t' -v c="$aligner_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    else
        echo "  Aligners: (no Aligner column)"
    fi
    # Footprints
    fp_col=$(echo "$colnames" | grep -n '^CmpFootprint$' | cut -d: -f1 | head -1)
    if [ -n "$fp_col" ]; then
        echo "  Footprints: $(awk -F'\t' -v c="$fp_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    else
        echo "  Footprints: (no CmpFootprint column)"
    fi
    # SNPClasses
    sc_col=$(echo "$colnames" | grep -n '^SNPClass$\|^VariantClass$' | cut -d: -f1 | head -1)
    if [ -n "$sc_col" ]; then
        echo "  SNPClasses: $(awk -F'\t' -v c="$sc_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    else
        echo "  SNPClasses: (no SNPClass/VariantClass column)"
    fi
    # Sample name examples (first 3)
    echo "  Sample examples: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | head -3 | tr '\n' ', ' | sed 's/,$//')"
    echo ""
done

echo "=== DONE ==="

