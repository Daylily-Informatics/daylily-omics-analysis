#!/usr/bin/env bash
set -euo pipefail
BD=/Users/jmajor/projects/daylily/daylily-omics-analysis/_analysis_data/agbt_benchmark_alignment_concordance_stats

echo "========================================"
echo "FULL AUDIT: all dirs under $BD"
echo "========================================"
echo ""

echo "=== ALL top-level items ==="
ls -1d "$BD"/*/ 2>/dev/null | sed "s|$BD/||" | sort
echo ""

echo "=== Directories containing giab_concordance_mqc.tsv ==="
find "$BD" -maxdepth 2 -name "giab_concordance_mqc.tsv" -type f 2>/dev/null | sort | while read -r f; do
    dir=$(dirname "$f" | sed "s|$BD/||")
    lines=$(wc -l < "$f")
    data=$((lines - 1))
    header=$(head -1 "$f" | cut -f1-5)
    samples=$(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | wc -l | tr -d ' ')
    echo "  DIR: $dir  |  DATA_ROWS: $data  |  UNIQUE_SAMPLES: $samples  |  HEADER_PREFIX: $header"
done
echo ""

echo "=== TEST_GROUPS in consolidation script ==="
grep -oP '"\K[^"]+(?=",\s*"[^"]*giab_concordance)' "$BD/consolidate_concordance.py" | sort
echo ""

echo "=== Directories WITH giab_concordance_mqc.tsv but NOT in consolidation script ==="
# Get test group names from the script
SCRIPT_GROUPS=$(grep -oP '"\K[^"]+(?=",\s*"[^"]*giab_concordance)' "$BD/consolidate_concordance.py" | sort)
# Get dirs with the file
find "$BD" -maxdepth 2 -name "giab_concordance_mqc.tsv" -type f 2>/dev/null | while read -r f; do
    dir=$(dirname "$f" | sed "s|$BD/||")
    # strip subdirectory paths for matching
    topdir=$(echo "$dir" | cut -d/ -f1)
    if ! echo "$SCRIPT_GROUPS" | grep -qx "$topdir"; then
        lines=$(wc -l < "$f")
        data=$((lines - 1))
        echo "  MISSING: $dir  |  DATA_ROWS: $data"
    fi
done
echo ""

echo "=== TEST_GROUPS in script but directory missing giab_concordance_mqc.tsv ==="
echo "$SCRIPT_GROUPS" | while read -r tg; do
    # find the relative path from the script
    rel=$(grep "\"$tg\"" "$BD/consolidate_concordance.py" | grep -oP '"[^"]*giab_concordance_mqc\.tsv"' | tr -d '"' | head -1)
    if [ -n "$rel" ] && [ ! -f "$BD/$rel" ]; then
        echo "  MISSING_FILE: $tg -> $BD/$rel"
    fi
done
echo ""

echo "=== Per-directory detail: columns, samples, callers, footprints ==="
find "$BD" -maxdepth 2 -name "giab_concordance_mqc.tsv" -type f 2>/dev/null | sort | while read -r f; do
    dir=$(dirname "$f" | sed "s|$BD/||")
    echo "--- $dir ---"
    ncols=$(head -1 "$f" | awk -F'\t' '{print NF}')
    echo "  Columns: $ncols"
    echo "  Column names: $(head -1 "$f" | tr '\t' ', ')"
    # Sample count
    echo "  Unique samples: $(awk -F'\t' 'NR>1{print $3}' "$f" | sort -u | wc -l | tr -d ' ')"
    # Callers (find caller column - typically col 18 or named SNVCaller)
    caller_col=$(head -1 "$f" | tr '\t' '\n' | grep -n "^SNVCaller$\|^Caller$" | cut -d: -f1 | head -1)
    if [ -n "$caller_col" ]; then
        echo "  Callers: $(awk -F'\t' -v c="$caller_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    fi
    # Aligners
    aligner_col=$(head -1 "$f" | tr '\t' '\n' | grep -n "^Aligner$" | cut -d: -f1 | head -1)
    if [ -n "$aligner_col" ]; then
        echo "  Aligners: $(awk -F'\t' -v c="$aligner_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    fi
    # Footprints
    fp_col=$(head -1 "$f" | tr '\t' '\n' | grep -n "^CmpFootprint$" | cut -d: -f1 | head -1)
    if [ -n "$fp_col" ]; then
        echo "  Footprints: $(awk -F'\t' -v c="$fp_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    fi
    # SNPClasses
    sc_col=$(head -1 "$f" | tr '\t' '\n' | grep -n "^SNPClass$" | cut -d: -f1 | head -1)
    if [ -n "$sc_col" ]; then
        echo "  SNPClasses: $(awk -F'\t' -v c="$sc_col" 'NR>1{print $c}' "$f" | sort -u | tr '\n' ', ' | sed 's/,$//')"
    fi
    echo ""
done

echo "=== DONE ==="

