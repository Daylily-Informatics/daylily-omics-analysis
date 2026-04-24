#!/bin/bash
# Dry-run all 6 COMMANDS_MUST_RUN.md test cases on the headnode
# Usage: bash dryrun_all_tests.sh <analysis_dir>
# e.g.: bash dryrun_all_tests.sh /fsx/analysis_results/ubuntu/dryrun-test-118/daylily-omics-analysis

set -uo pipefail

ADIR="${1:?Usage: $0 <analysis_dir>}"
cd "$ADIR" || { echo "FATAL: cannot cd to $ADIR"; exit 1; }

echo "=== Pulling latest main ==="
git pull origin main 2>&1
echo ""

# Source daylily init
source dyoainit 2>&1
dy-a slurm hg38 2>&1
echo ""

PASS=0
FAIL=0
RESULTS=""

run_test() {
    local name="$1"
    local samples="$2"
    local units="$3"
    shift 3
    local cmd="$*"

    echo "============================================================"
    echo "TEST: $name"
    echo "============================================================"

    cp "$samples" config/samples.tsv 2>&1
    awk 'NR <= 4' "$units" > config/units.tsv
    echo "Staged $(tail -n +2 config/units.tsv | grep -c '[^[:space:]]') unit rows"

    echo "CMD: $cmd"
    OUTPUT=$(eval "$cmd" 2>&1)
    RC=$?
    echo "$OUTPUT" | tail -30
    echo ""
    echo "RETURN CODE: $RC"

    # Check for common errors
    if echo "$OUTPUT" | grep -q "MissingInputException\|AmbiguousRuleException\|WorkflowError\|SyntaxError"; then
        echo "RESULT: FAIL (error detected)"
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}\n  FAIL: $name (RC=$RC, error in output)"
    elif [ $RC -ne 0 ]; then
        echo "RESULT: FAIL (non-zero exit)"
        FAIL=$((FAIL + 1))
        RESULTS="${RESULTS}\n  FAIL: $name (RC=$RC)"
    else
        JOBS=$(echo "$OUTPUT" | grep -oP 'Job stats.*?(\d+)' | tail -1 || echo "")
        JOBCOUNT=$(echo "$OUTPUT" | grep -c "^[[:space:]]*[a-z_]" || echo "?")
        echo "RESULT: PASS"
        PASS=$((PASS + 1))
        RESULTS="${RESULTS}\n  PASS: $name (RC=$RC)"
    fi
    echo ""
}

# Test 1: Hybrid Ultima+ONT
run_test "Hybrid Ultima+ONT" \
    ".test_data/data/hybrid/ultima_ont_full_cov.samples.tsv" \
    ".test_data/data/hybrid/ultima_ont_full_cov.units.tsv" \
    "dy-r produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"

# Test 2: Hybrid Ilmn+ONT
run_test "Hybrid Ilmn+ONT" \
    ".test_data/data/hybrid/ilmn_ont_full_cov.samples.tsv" \
    ".test_data/data/hybrid/ilmn_ont_full_cov.units.tsv" \
    "dy-r produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"

# Test 3: ONT only
run_test "ONT only" \
    ".test_data/data/ont/ont_full_cov.samples.tsv" \
    ".test_data/data/ont/ont_full_cov.units.tsv" \
    "dy-r produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"

# Test 4: ILMN ONLY
run_test "ILMN ONLY" \
    ".test_data/data/ilmn/ilmn_full_cov.samples.tsv" \
    ".test_data/data/ilmn/ilmn_full_cov.units.tsv" \
    "dy-r produce_sentieon_bwa_sort_bam produce_bwa_mem2_sort_bam dedup_doppelmark dedup_sentieon produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"

# Test 5: PB only
run_test "PB only" \
    ".test_data/data/pacbio/pacbio_full_cov.samples.tsv" \
    ".test_data/data/pacbio/pacbio_full_cov.units.tsv" \
    "dy-r produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"

# Test 6: Ultima only
run_test "Ultima only" \
    ".test_data/data/ultima/ultima_full_cov.samples.tsv" \
    ".test_data/data/ultima/ultima_full_cov.units.tsv" \
    "dy-r produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"

echo "============================================================"
echo "SUMMARY: $PASS passed, $FAIL failed"
echo -e "$RESULTS"
echo "============================================================"
