#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

echo "=== Pulling latest code on all 3 analysis dirs ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$d/daylily-omics-analysis"
    echo "--- $d ---"
    cd "$DIR"
    git pull origin feat/modular-hybrid-workflows 2>&1 | tail -3
    echo ""
done

echo "=== Removing ALL stale concordance outputs ==="
for d in test-sentdhipmr-3x test-sentdhuomr-3x test-sentdhupmr-3x; do
    DIR="$BASE/$d/daylily-omics-analysis"
    echo "--- $d ---"
    rm -f "$DIR/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    find "$DIR/results/" -name 'concordance.done' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name 'concordance.fofn' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name 'concordance.fin.cmds' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -name 'concordance.done.SKIPPED' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*concordance*' -name '*.log' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*concordance*' -name '*.bench.tsv' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*vcfeval*' -type f -delete 2>/dev/null || true
    find "$DIR/results/" -path '*vcfeval*' -type d -empty -delete 2>/dev/null || true
    find "$DIR/results/" -path '*concordance*' -name '*.mqc.tsv' -type f -delete 2>/dev/null || true
    echo "  Cleaned"
done

echo ""
echo "=== DRY-RUN concordance with explicit config ==="

# sentdhipmr
echo ""
echo "--- test-sentdhipmr-3x (sentmm2 + sentdhipmr) ---"
cd "$BASE/test-sentdhipmr-3x/daylily-omics-analysis"
source dyoainit 2>/dev/null
source bin/day_activate slurm hg38_broad 2>/dev/null
bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 --config aligners="['sentmm2']" snv_callers="['sentdhipmr']" 2>&1 | tail -60

# sentdhuomr
echo ""
echo "--- test-sentdhuomr-3x (ug + sentdhuomr) ---"
cd "$BASE/test-sentdhuomr-3x/daylily-omics-analysis"
source dyoainit 2>/dev/null
source bin/day_activate slurm hg38_broad 2>/dev/null
bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 --config aligners="['ug']" snv_callers="['sentdhuomr']" 2>&1 | tail -60

# sentdhupmr
echo ""
echo "--- test-sentdhupmr-3x (ug + sentdhupmr) ---"
cd "$BASE/test-sentdhupmr-3x/daylily-omics-analysis"
source dyoainit 2>/dev/null
source bin/day_activate slurm hg38_broad 2>/dev/null
bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 --config aligners="['ug']" snv_callers="['sentdhupmr']" 2>&1 | tail -60

echo ""
echo "=== DRY-RUN COMPLETE ==="

