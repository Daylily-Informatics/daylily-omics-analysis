#!/usr/bin/env bash
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
echo "=== Line counts ==="
wc -l etc/deep19/giab_concordance_mqc.tsv etc/deep19b/giab_concordance_mqc.tsv etc/ont/giab_concordance_mqc.tsv etc/ont_all/giab_concordance_mqc.tsv
echo ""
echo "=== Running consolidation ==="
conda run -n DAY-EC python3 scripts/tmp_consolidate_concordance.py

