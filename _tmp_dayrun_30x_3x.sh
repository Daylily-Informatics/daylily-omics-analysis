#!/usr/bin/env bash
# day_run wrapper for HG003 30x + 3x pangenome concordance
bash bin/day_run \
  produce_snv_concordances \
  --config \
    "aligners=['pangenome_sr']" \
    "dedupers=['spmd']" \
    "snv_callers=['sentpg']" \
  -p -j 20 -k -T 1 \
  2>&1 | tee /tmp/pangenome_30x_3x_run.log

