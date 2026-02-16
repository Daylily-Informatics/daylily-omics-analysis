#!/usr/bin/env bash
# Relaunch test 3 (ONT only) with the CORRECT target: produce_sentdont_vcf
# (was incorrectly produce_sentD_vcf which uses the Illumina DNAscope model)

set -euo pipefail

WORK_ROOT="/fsx/analysis_results/ubuntu/single-unit-runs"
adir="$WORK_ROOT/test-3/daylily-omics-analysis"
sess="test3_fix"

echo "── Relaunching Test 3 (ONT only) with produce_sentdont_vcf ──"

# Verify clone exists
if [ ! -d "$adir/.git" ]; then
    echo "ERROR: clone missing at $adir"
    exit 1
fi

# Clean old results
rm -rf "$adir/results" "$adir/.snakemake" "$adir/_test_3.log" "$adir/_test_3_fix.log" 2>/dev/null || true

# Write corrected runner script
cat > "$adir/_run_test3_fix.sh" <<'RUNNER'
#!/usr/bin/env bash
cd /fsx/analysis_results/ubuntu/single-unit-runs/test-3/daylily-omics-analysis || exit 1

echo "=== TEST 3 FIX: ONT only (produce_sentdont_vcf) ==="
echo "Started: $(date)"

# Activation uses unguarded vars — disable strict modes
set +euo pipefail
source bin/day_activate slurm hg38
set -uo pipefail

CMD="bin/day_run produce_sentdont_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
echo "Running: $CMD"
$CMD
RC=$?

echo ""
echo "TEST_3_FIX_RETURN_CODE: $RC"
echo "Finished: $(date)"
exit $RC
RUNNER
chmod +x "$adir/_run_test3_fix.sh"

# Kill old sessions
tmux kill-session -t test3 2>/dev/null || true
tmux kill-session -t "$sess" 2>/dev/null || true

# Launch with remain-on-exit
tmux new-session -d -s "$sess" "bash -l $adir/_run_test3_fix.sh 2>&1 | tee $adir/_test_3_fix.log"
tmux set-option -t "$sess" remain-on-exit on

echo "tmux session: $sess"
echo "Monitor:  tmux attach -t $sess"
echo "Log:      tail -f $adir/_test_3_fix.log"

