#!/usr/bin/env bash
# Relaunch all 6 single-unit tests in tmux sessions.
# The cloned repos + subsetted configs from launch_single_unit_tests.sh
# are already in place — just fix the runner scripts and relaunch.

set -euo pipefail

WORK_ROOT="/fsx/analysis_results/ubuntu/single-unit-runs"

declare -a LABELS=( "Hybrid Ultima+ONT" "Hybrid Ilmn+ONT" "ONT only" "ILMN only" "PB only" "Ultima only" )
declare -a CMDS=(
    "bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
    "bin/day_run produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
    "bin/day_run produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
    "bin/day_run produce_sentieon_bwa_sort_bam produce_bwa_mem2_sort_bam dedup_doppelmark dedup_sentieon produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
    "bin/day_run produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
    "bin/day_run produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"
)

for i in 1 2 3 4 5 6; do
    idx=$((i - 1))
    label="${LABELS[$idx]}"
    cmd="${CMDS[$idx]}"
    adir="$WORK_ROOT/test-${i}/daylily-omics-analysis"
    sess="test${i}"
    logf="$adir/_test_${i}.log"

    echo "── Test $i ($label) ──"

    # Verify clone exists
    if [ ! -d "$adir/.git" ]; then
        echo "  ERROR: clone missing at $adir"
        continue
    fi

    # Write a robust runner (no set -e during activation)
    cat > "$adir/_run_test.sh" <<RUNNER
#!/usr/bin/env bash
cd "$adir" || exit 1

echo "=== TEST $i: $label ==="
echo "Started: \$(date)"

# Activation uses unguarded vars — disable strict modes
set +euo pipefail
source bin/day_activate slurm hg38
set -uo pipefail

echo "Running: $cmd"
$cmd
RC=\$?

echo ""
echo "TEST_${i}_RETURN_CODE: \$RC"
echo "Finished: \$(date)"
exit \$RC
RUNNER
    chmod +x "$adir/_run_test.sh"

    # Clean old results so snakemake starts fresh
    rm -rf "$adir/results" "$adir/.snakemake" 2>/dev/null || true

    # Kill old session if present
    tmux kill-session -t "$sess" 2>/dev/null || true

    # Launch with remain-on-exit so we can inspect after completion
    tmux new-session -d -s "$sess" "bash -l $adir/_run_test.sh 2>&1 | tee $logf"
    tmux set-option -t "$sess" remain-on-exit on

    echo "  tmux session: $sess"
done

echo ""
echo "All 6 tmux sessions launched."
tmux ls
echo ""
echo "Monitor:  tmux attach -t test1   (test2..test6)"
echo "Logs:     tail -f $WORK_ROOT/test-N/daylily-omics-analysis/_test_N.log"

