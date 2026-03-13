#!/usr/bin/env bash
export PATH=/opt/slurm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
SAMPLE="HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ"
DCHRM="21"
STD_TMP="$STD_DIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhiom/vcfs/$DCHRM/tmp"
REF_TMP="$REF_DIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhiomr/vcfs/$DCHRM/tmp"

echo "=== SLURM QUEUE ==="
squeue -u ubuntu 2>/dev/null

echo ""
echo "=== STD tmp dir ==="
ls -lh "$STD_TMP/" 2>&1

echo ""
echo "=== merged_diff.bed ==="
wc -l "$STD_TMP/merged_diff.bed" 2>/dev/null || echo "MISSING"
head -5 "$STD_TMP/merged_diff.bed" 2>/dev/null

echo ""
echo "=== selected.bed ==="
wc -l "$STD_TMP/selected.bed" 2>/dev/null || echo "MISSING"

echo ""
echo "=== hybrid_mapq0.ex1000.bed ==="
wc -l "$STD_TMP/hybrid_mapq0.ex1000.bed" 2>/dev/null || echo "MISSING"

echo ""
echo "=== REF tmp dir ==="
ls -lh "$REF_TMP/" 2>&1

echo ""
echo "=== STD TMUX (last 10) ==="
tmux capture-pane -t hiom_std_chr21 -p -S -10 2>/dev/null

echo ""
echo "=== REF TMUX (last 10) ==="
tmux capture-pane -t hiom_ref_chr21 -p -S -10 2>/dev/null

