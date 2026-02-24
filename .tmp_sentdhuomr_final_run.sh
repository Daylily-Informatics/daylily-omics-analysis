#!/bin/bash
# Final sentdhuomr 6x6 grid dry-run and production script
# Runs in the existing analysis directory

set -e

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/sentdhuomr_6x6_grid/daylily-omics-analysis"
GENOME_BUILD="hg38_broad"
EXECUTOR="slurm"
TARGETS="produce_sentdhuomr_vcf produce_snv_concordances"
SNAKEMAKE_FLAGS="-p -k -j 40 -T 1"

echo "=== Sentdhuomr 6x6 Grid Analysis ==="
echo "Analysis directory: $ANALYSIS_DIR"
echo "Genome Build: $GENOME_BUILD"
echo "Executor: $EXECUTOR"
echo "Targets: $TARGETS"
echo ""

cd "$ANALYSIS_DIR"

# Restore workflow directory if needed
if [ ! -f "workflow/Snakefile" ]; then
    echo "Restoring workflow directory..."
    git checkout HEAD -- workflow/
fi

echo "=== Running DRY-RUN ==="
source dyoainit
source bin/day_activate "$EXECUTOR" "$GENOME_BUILD" "remote"
bash bin/day_run $TARGETS $SNAKEMAKE_FLAGS -n

DRY_RUN_EXIT=$?
if [ $DRY_RUN_EXIT -ne 0 ]; then
    echo ""
    echo "ERROR: Dry-run failed with exit code $DRY_RUN_EXIT"
    exit $DRY_RUN_EXIT
fi

echo ""
echo "=== Dry-run successful ==="
echo "=== Running PRODUCTION ==="
source dyoainit
source bin/day_activate "$EXECUTOR" "$GENOME_BUILD" "remote"
bash bin/day_run $TARGETS $SNAKEMAKE_FLAGS

PROD_EXIT=$?
if [ $PROD_EXIT -ne 0 ]; then
    echo ""
    echo "ERROR: Production run failed with exit code $PROD_EXIT"
    exit $PROD_EXIT
fi

echo ""
echo "=== Production run complete ==="
echo "Analysis results available at: $ANALYSIS_DIR"

