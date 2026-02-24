#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== STD: check snakemake completion in log ==="
ssh -i "$KEY" "$HN" "grep -E '(steps done|Error|error|Exiting|complete|Nothing to be done|Shutting)' /tmp/hiom_std_chr21.log 2>/dev/null | tail -10"

echo ""
echo "=== STD: list output files ==="
ssh -i "$KEY" "$HN" "find $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/ -name '*.vcf.gz' -o -name '*.bam' -o -name '*.bed' 2>/dev/null | sort"

echo ""
echo "=== STD: snakemake log (last 20 lines of snakemake output) ==="
ssh -i "$KEY" "$HN" "grep -E '(rule |Finished|steps done|Error|Select jobs|Submitted|Exiting)' /tmp/hiom_std_chr21.log 2>/dev/null | tail -20"

