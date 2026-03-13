#!/usr/bin/env bash
set -euo pipefail

source ~/.bashrc

WORKDIR="/fsx/analysis_results/ubuntu/pg_ilmn_1x_test_20260222/daylily-omics-analysis"
cd "$WORKDIR"
source dyoainit
source bin/day_activate slurm hg38
bash bin/day_run produce_snv_concordances -p -j 1 -k -T 1 --config aligners="['pangenome_sr']" dedupers="['spmd']" snv_callers="['sentpg']" -n

