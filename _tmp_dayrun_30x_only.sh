#!/usr/bin/env bash
# Restart 30x pangenome + concordance only (3x already done)
bash bin/day_run \
  produce_snv_concordances \
  --config \
    "aligners=['pangenome_sr']" \
    "dedupers=['spmd']" \
    "snv_callers=['sentpg']" \
  -p -j 20 -k -T 1 \
  --rerun-incomplete \
  2>&1 | tee /tmp/pangenome_30x_restart_run.log

