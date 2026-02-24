#!/bin/bash
set -euo pipefail
HIOM_DIR="/fsx/analysis_results/ubuntu/cmr-hiom-mod-20260218-163021/daylily-omics-analysis"
HUOM_DIR="/fsx/analysis_results/ubuntu/cmr-huom-mod-20260218-163021/daylily-omics-analysis"
for DIR in "$HIOM_DIR" "$HUOM_DIR"; do
    echo "=== Processing $DIR ==="
    cd "$DIR"
    git pull origin feat/modular-hybrid-workflows 2>&1 || echo "git pull failed (non-fatal)"
    find "$DIR/results" -name "stage1_hap.bam" -type f 2>/dev/null | while read bam; do
        bai="${bam}.bai"
        if [ ! -f "$bai" ]; then
            echo "Indexing: $bam"
            samtools index "$bam" 2>&1
            echo "  Created: $bai"
        else
            echo "Already indexed: $bam"
        fi
    done
    echo ""
done
echo "=== Done ==="
