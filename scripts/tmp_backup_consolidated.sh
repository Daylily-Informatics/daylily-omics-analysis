#!/bin/bash
set -euo pipefail
SRC="_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv"
if [ -f "$SRC" ]; then
    TS=$(date +%Y%m%d_%H%M%S)
    DEST="${SRC}.backup_${TS}"
    cp "$SRC" "$DEST"
    echo "Backed up to: $DEST"
    wc -l "$SRC" "$DEST"
else
    echo "ERROR: $SRC does not exist"
    exit 1
fi

