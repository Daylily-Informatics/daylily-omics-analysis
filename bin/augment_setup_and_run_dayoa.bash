#!/bin/bash

$GENOME_CODE=$2
$LOCAL_OR_SLURM=$1
$SNAKEMAKE_TARGETS=$3 # " produce_snv_concordances produce_alignstats produce_sentdhio_vcf "
$SNAKEMAKE_FLAGS=$4 # " -p -j 10 -k -T 1 "
$DRY_RUN=$5 # " -n "

source dyoainit && source bin/day_activate "$LOCAL_OR_SLURM" "$GENOME_CODE" && bin/day_run "$SNAKEMAKE_TARGETS" "$SNAKEMAKE_FLAGS" "$DRY_RUN"
