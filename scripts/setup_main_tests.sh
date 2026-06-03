#!/bin/bash
# setup_main_tests.sh - Runs on headnode
# Creates fresh clones from main, copies test data, launches tmux sessions

echo "=========================================="
echo "Setting up tests 2, 4, 1 from main branch"
echo "=========================================="

BASE="/fsx/analysis_results/ubuntu/single-unit-runs"

stage_config() {
    local workdir="$1"
    local samples="$2"
    local units="$3"
    cp "$workdir/$samples" "$workdir/config/samples.tsv"
    awk 'NR <= 4' "$workdir/$units" > "$workdir/config/units.tsv"
}

# Remove old test dirs if they exist
for d in test-2-main test-4-main test-1-main; do
    if [ -d "$BASE/$d" ]; then
        echo "Removing existing $BASE/$d ..."
        rm -rf "$BASE/$d"
    fi
done

# --- Clone test-2-main (Hybrid Ilmn+ONT) ---
echo ""
echo "=== Cloning test-2-main ==="
day-clone -w ssh -t main -d single-unit-runs/test-2-main
T2="$BASE/test-2-main/daylily-omics-analysis"
if [ ! -d "$T2" ]; then
    echo "day-clone path failed; falling back to git clone"
    mkdir -p "$BASE/test-2-main"
    git clone --branch main git@github.com:lsmc-bio/daylily-omics-analysis.git "$T2"
fi
stage_config "$T2" .test_data/data/hybrid/ilmn_ont_full_cov.samples.tsv .test_data/data/hybrid/ilmn_ont_full_cov.units.tsv
echo "test-2-main ready at $T2"

# --- Clone test-4-main (ILMN only) ---
echo ""
echo "=== Cloning test-4-main ==="
day-clone -w ssh -t main -d single-unit-runs/test-4-main
T4="$BASE/test-4-main/daylily-omics-analysis"
if [ ! -d "$T4" ]; then
    echo "day-clone path failed; falling back to git clone"
    mkdir -p "$BASE/test-4-main"
    git clone --branch main git@github.com:lsmc-bio/daylily-omics-analysis.git "$T4"
fi
stage_config "$T4" .test_data/data/ilmn/ilmn_full_cov.samples.tsv .test_data/data/ilmn/ilmn_full_cov.units.tsv
echo "test-4-main ready at $T4"

# --- Clone test-1-main (Hybrid Ultima+ONT) ---
echo ""
echo "=== Cloning test-1-main ==="
day-clone -w ssh -t main -d single-unit-runs/test-1-main
T1="$BASE/test-1-main/daylily-omics-analysis"
if [ ! -d "$T1" ]; then
    echo "day-clone path failed; falling back to git clone"
    mkdir -p "$BASE/test-1-main"
    git clone --branch main git@github.com:lsmc-bio/daylily-omics-analysis.git "$T1"
fi
stage_config "$T1" .test_data/data/hybrid/ultima_ont_full_cov.samples.tsv .test_data/data/hybrid/ultima_ont_full_cov.units.tsv
echo "test-1-main ready at $T1"

echo ""
echo "=========================================="
echo "Launching tmux sessions"
echo "=========================================="

# Kill existing sessions with these names
for s in test-2-main test-4-main test-1-main; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

# Test 2: Hybrid Ilmn+ONT
tmux new-session -d -s test-2-main
tmux send-keys -t test-2-main "cd $T2 && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k 2>&1 | tee _test_2_main.log; echo 'TEST_2_MAIN_RETURN_CODE: '\$?" Enter
echo "Launched: test-2-main (Hybrid Ilmn+ONT)"
sleep 5

# Test 4: ILMN only
tmux new-session -d -s test-4-main
tmux send-keys -t test-4-main "cd $T4 && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats -p -k -j 20 2>&1 | tee _test_4_main.log; echo 'TEST_4_MAIN_RETURN_CODE: '\$?" Enter
echo "Launched: test-4-main (ILMN only)"
sleep 5

# Test 1: Hybrid Ultima+ONT
tmux new-session -d -s test-1-main
tmux send-keys -t test-1-main "cd $T1 && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k 2>&1 | tee _test_1_main.log; echo 'TEST_1_MAIN_RETURN_CODE: '\$?" Enter
echo "Launched: test-1-main (Hybrid Ultima+ONT)"

echo ""
echo "=========================================="
echo "All sessions launched. Active tmux sessions:"
echo "=========================================="
tmux ls
echo ""
echo "DONE"
