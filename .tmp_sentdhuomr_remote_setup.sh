#!/bin/bash

# Remote dry-run + production script for sentdhuomr 6x6 grid analysis
# Runs both in sequence in the same directory

ANALYSIS_DESC="sentdhuomr_6x6_grid"
GENOME_BUILD="hg38_broad"
EXECUTOR="slurm"
TARGETS="produce_sentdhuomr_vcf produce_snv_concordances"
SNAKEMAKE_FLAGS="-p -k -j 40 -T 1"

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/$ANALYSIS_DESC/daylily-omics-analysis"

echo "=== Sentdhuomr 6x6 Grid Analysis ==="
echo "Analysis directory: $ANALYSIS_DIR"
echo "Genome Build: $GENOME_BUILD"
echo "Executor: $EXECUTOR"
echo "Targets: $TARGETS"
echo ""

if [ ! -d "$ANALYSIS_DIR" ]; then
    echo "ERROR: Analysis directory not found at $ANALYSIS_DIR"
    exit 1
fi

cd "$ANALYSIS_DIR"

echo "=== Running DRY-RUN ==="
source dyoainit
source bin/day_activate "$EXECUTOR" "$GENOME_BUILD"
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
source bin/day_activate "$EXECUTOR" "$GENOME_BUILD"
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

