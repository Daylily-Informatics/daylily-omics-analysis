#!/bin/sh
set -e
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
git add -A
git diff --cached --stat
git commit -m "fix: wire roche_filter_variants into concordance chain

GATK HC now outputs *.gatk_raw.vcf.gz (intermediate).
roche_filter_variants produces canonical *.snv.sort.vcf.gz so
prep_for_concordance_check consumes filtered VCFs instead of
bypassing the Roche filter step."
git push origin feat/roche-sbxd-support
echo "DONE_OK"

