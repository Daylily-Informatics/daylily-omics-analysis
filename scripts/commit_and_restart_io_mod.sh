#!/bin/bash
# Commit the -b to --interval fix and restart the modular Illumina+ONT test

set -e
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

# Stage and commit
git add workflow/rules/common.smk workflow/rules/sent_hybrid_ilmn_ont_modular.smk workflow/rules/sent_hybrid_ug_ont_modular.smk
git commit -m "fix: use --interval instead of -b for sentieon driver in modular workflows

The modular hybrid workflows call sentieon driver directly (not sentieon-cli).
sentieon driver requires --interval flag for BED files, not -b shorthand.

Added get_diploid_bed_interval_arg() function in common.smk and updated all
6 occurrences in both modular hybrid workflow files."

git push origin feat/modular-hybrid-workflows

echo "Committed and pushed fix"

