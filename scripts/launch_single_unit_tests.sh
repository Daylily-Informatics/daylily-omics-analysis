#!/usr/bin/env bash
# Launch 6 single-unit real-run tests, each in its own tmux session.
# Each test gets its own git-clone so config/ files don't collide.
#
# Usage: bash launch_single_unit_tests.sh
#
# Assumes this script runs on the headnode (or is sourced via bash -l).

set -euo pipefail

BASE_REPO="/fsx/analysis_results/ubuntu/dryrun-118/daylily-omics-analysis"
WORK_ROOT="/fsx/analysis_results/ubuntu/single-unit-runs"
mkdir -p "$WORK_ROOT"

# ── helpers ────────────────────────────────────────────────────────────
subset_config() {
    # $1 = source samples.tsv  $2 = source units.tsv  $3 = dest dir
    local src_samp="$1" src_units="$2" dest="$3"
    mkdir -p "$dest"

    # units: header + first data row
    head -n 2 "$src_units" > "$dest/units.tsv"

    # samples: header + only the SAMPLEID that appears in that first data row
    local sample_id
    sample_id=$(awk -F'\t' 'NR==2{print $2}' "$src_units")
    head -n 1 "$src_samp" > "$dest/samples.tsv"
    awk -F'\t' -v sid="$sample_id" 'NR>1 && $1==sid' "$src_samp" >> "$dest/samples.tsv"
}

clone_and_prep() {
    # $1=test_num  $2=label  $3=samples_tsv  $4=units_tsv  $5=command (no -n)
    local tnum="$1" label="$2" samp="$3" units="$4" cmd="$5"
    local tdir="$WORK_ROOT/test-${tnum}"

    echo "── Test $tnum ($label) ──────────────────────────"

    # Clone repo (local clone uses hardlinks, fast)
    if [ -d "$tdir/daylily-omics-analysis/.git" ]; then
        echo "  clone exists, pulling latest..."
        (cd "$tdir/daylily-omics-analysis" && git pull origin main --ff-only) || true
    else
        rm -rf "$tdir"
        mkdir -p "$tdir"
        git clone --local "$BASE_REPO" "$tdir/daylily-omics-analysis"
    fi

    local adir="$tdir/daylily-omics-analysis"

    # Subset config
    subset_config "$adir/$samp" "$adir/$units" "$adir/config"

    echo "  samples.tsv rows: $(wc -l < "$adir/config/samples.tsv")"
    echo "  units.tsv rows:   $(wc -l < "$adir/config/units.tsv")"
    echo "  sample: $(awk -F'\t' 'NR==2{print $2}' "$adir/config/units.tsv")"

    # Build the runner script inside the clone
    cat > "$adir/_run_test.sh" <<RUNNER
#!/usr/bin/env bash
set -eo pipefail
cd "$adir"
echo "=== TEST $tnum: $label ==="
echo "Started: \$(date)"
set +u
source bin/day_activate slurm hg38
set -u
echo "Running: $cmd"
${cmd//dy-r/bin/day_run}
RC=\$?
echo ""
echo "TEST_${tnum}_RETURN_CODE: \$RC"
echo "Finished: \$(date)"
RUNNER
    chmod +x "$adir/_run_test.sh"

    # Launch tmux session
    local sess="test${tnum}"
    tmux kill-session -t "$sess" 2>/dev/null || true
    tmux new-session -d -s "$sess" "bash -l $adir/_run_test.sh 2>&1 | tee $adir/_test_${tnum}.log"
    echo "  tmux session: $sess"
}

# ── tests ──────────────────────────────────────────────────────────────
echo "Launching 6 single-unit real-run tests..."
echo ""

clone_and_prep 1 "Hybrid Ultima+ONT" \
    ".test_data/data/hybrid/ultima_ont_full_cov.samples.tsv" \
    ".test_data/data/hybrid/ultima_ont_full_cov.units.tsv" \
    "dy-r produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"

clone_and_prep 2 "Hybrid Ilmn+ONT" \
    ".test_data/data/hybrid/ilmn_ont_full_cov.samples.tsv" \
    ".test_data/data/hybrid/ilmn_ont_full_cov.units.tsv" \
    "dy-r produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"

clone_and_prep 3 "ONT only" \
    ".test_data/data/ont/ont_full_cov.samples.tsv" \
    ".test_data/data/ont/ont_full_cov.units.tsv" \
    "dy-r produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"

clone_and_prep 4 "ILMN only" \
    ".test_data/data/ilmn/ilmn_full_cov.samples.tsv" \
    ".test_data/data/ilmn/ilmn_full_cov.units.tsv" \
    "dy-r produce_sentieon_bwa_sort_bam produce_bwa_mem2_sort_bam dedup_doppelmark dedup_sentieon produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"

clone_and_prep 5 "PB only" \
    ".test_data/data/pacbio/pacbio_full_cov.samples.tsv" \
    ".test_data/data/pacbio/pacbio_full_cov.units.tsv" \
    "dy-r produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"

clone_and_prep 6 "Ultima only" \
    ".test_data/data/ultima/ultima_full_cov.samples.tsv" \
    ".test_data/data/ultima/ultima_full_cov.units.tsv" \
    "dy-r produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k"

echo ""
echo "All 6 tmux sessions launched."
echo "Monitor with:  tmux ls"
echo "Attach with:   tmux attach -t test1  (or test2..test6)"
echo "Check logs:    tail -f $WORK_ROOT/test-N/daylily-omics-analysis/_test_N.log"

