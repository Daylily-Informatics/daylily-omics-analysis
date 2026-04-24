#!/bin/bash
# launch_full_manifest_tests.sh - Runs on headnode
# Clones from main, caps units manifests, launches tmux sessions

echo "=========================================="
echo "Full-manifest tests: ONT, PacBio, Ultima"
echo "=========================================="

BASE="/fsx/analysis_results/ubuntu/single-unit-runs"

stage_config() {
    local workdir="$1"
    local samples="$2"
    local units="$3"
    cp "$workdir/$samples" "$workdir/config/samples.tsv"
    awk 'NR <= 4' "$workdir/$units" > "$workdir/config/units.tsv"
}

# Remove old dirs if they exist
for d in test-3-ont test-5-pacbio test-6-ultima; do
    if [ -d "$BASE/$d" ]; then
        echo "Removing existing $BASE/$d ..."
        rm -rf "$BASE/$d"
    fi
done

# --- Clone test-3-ont ---
echo ""
echo "=== Cloning test-3-ont (ONT only, full manifest) ==="
day-clone -w ssh -t main -d single-unit-runs/test-3-ont
T3="$BASE/test-3-ont/daylily-omics-analysis"
if [ ! -d "$T3" ]; then
    echo "FATAL: day-clone failed for test-3-ont"; exit 1
fi
stage_config "$T3" .test_data/data/ont/ont_full_cov.samples.tsv .test_data/data/ont/ont_full_cov.units.tsv
echo "test-3-ont ready at $T3"
echo "  Samples: $(tail -n +2 $T3/config/samples.tsv | grep -c '[^[:space:]]') samples"
echo "  Units:   $(tail -n +2 $T3/config/units.tsv   | grep -c '[^[:space:]]') units"

# --- Clone test-5-pacbio ---
echo ""
echo "=== Cloning test-5-pacbio (PacBio only, full manifest) ==="
day-clone -w ssh -t main -d single-unit-runs/test-5-pacbio
T5="$BASE/test-5-pacbio/daylily-omics-analysis"
if [ ! -d "$T5" ]; then
    echo "FATAL: day-clone failed for test-5-pacbio"; exit 1
fi
stage_config "$T5" .test_data/data/pacbio/pacbio_full_cov.samples.tsv .test_data/data/pacbio/pacbio_full_cov.units.tsv
echo "test-5-pacbio ready at $T5"
echo "  Samples: $(tail -n +2 $T5/config/samples.tsv | grep -c '[^[:space:]]') samples"
echo "  Units:   $(tail -n +2 $T5/config/units.tsv   | grep -c '[^[:space:]]') units"

# --- Clone test-6-ultima ---
echo ""
echo "=== Cloning test-6-ultima (Ultima only, full manifest) ==="
day-clone -w ssh -t main -d single-unit-runs/test-6-ultima
T6="$BASE/test-6-ultima/daylily-omics-analysis"
if [ ! -d "$T6" ]; then
    echo "FATAL: day-clone failed for test-6-ultima"; exit 1
fi
stage_config "$T6" .test_data/data/ultima/ultima_full_cov.samples.tsv .test_data/data/ultima/ultima_full_cov.units.tsv
echo "test-6-ultima ready at $T6"
echo "  Samples: $(tail -n +2 $T6/config/samples.tsv | grep -c '[^[:space:]]') samples"
echo "  Units:   $(tail -n +2 $T6/config/units.tsv   | grep -c '[^[:space:]]') units"

echo ""
echo "=========================================="
echo "Launching tmux sessions"
echo "=========================================="

# Kill existing sessions with these names
for s in test-3-ont test-5-pacbio test-6-ultima; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

# Test 3: ONT only (full manifest)
tmux new-session -d -s test-3-ont
tmux send-keys -t test-3-ont "cd $T3 && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_sentdont_vcf produce_alignstats produce_snv_concordances -p -j 20 -k 2>&1 | tee _test_3_ont.log; echo 'TEST_3_ONT_RETURN_CODE: '\$?" Enter
echo "Launched: test-3-ont (ONT only, capped at 3 units)"
sleep 5

# Test 5: PacBio only (full manifest)
tmux new-session -d -s test-5-pacbio
tmux send-keys -t test-5-pacbio "cd $T5 && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k 2>&1 | tee _test_5_pacbio.log; echo 'TEST_5_PACBIO_RETURN_CODE: '\$?" Enter
echo "Launched: test-5-pacbio (PacBio only, capped at 3 units)"
sleep 5

# Test 6: Ultima only (full manifest)
tmux new-session -d -s test-6-ultima
tmux send-keys -t test-6-ultima "cd $T6 && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k 2>&1 | tee _test_6_ultima.log; echo 'TEST_6_ULTIMA_RETURN_CODE: '\$?" Enter
echo "Launched: test-6-ultima (Ultima only, capped at 3 units)"

echo ""
echo "=========================================="
echo "All sessions launched. Active tmux sessions:"
echo "=========================================="
tmux ls
echo ""
echo "DONE"
