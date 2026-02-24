#!/usr/bin/env bash
# day_run wrapper for HG003 30x pangenome concordance
# Called AFTER dyoainit + day_activate have been sourced in the shell
bash bin/day_run \
  produce_snv_concordances \
  --config \
    "aligners=['pangenome_sr']" \
    "dedupers=['spmd']" \
    "snv_callers=['sentpg']" \
    "remote_samples_table='.test_data/data/hg003_30x_hg38.samples.tsv'" \
    "remote_units_table='.test_data/data/hg003_30x_hg38.units.tsv'" \
  -p -j 20 -k -T 1 \
  2>&1 | tee /tmp/pangenome_30x_hg003_run.log

