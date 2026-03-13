#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

echo "=== GIT STATUS ==="
git status --short workflow/rules/

echo "=== GIT ADD ==="
git add \
  workflow/rules/sent_hybrid_ilmn_ont_modular.smk \
  workflow/rules/sent_hybrid_ilmn_pb_modular.smk \
  workflow/rules/sent_hybrid_roche_ont_modular.smk \
  workflow/rules/sent_hybrid_roche_pb_modular.smk \
  workflow/rules/sent_hybrid_ug_pb_modular.smk

echo "=== GIT COMMIT ==="
git commit -m "fix: reheader LR+stage3 BAMs before DNAscope pass1/pass2 for single-sample VCFs

Modular pipeline was feeding BAMs with mismatched SM tags to sentieon driver,
producing multi-sample VCFs that caused Duplicated sample name errors in
the transfer step. Now reheaders LR CRAM and stage3 BAM to use cluster_sample
SM tag before DNAscope calls, matching sentieon-cli --rgsm/--replace_rg behavior.

Files: ilmn_ont(pass1+pass2), ilmn_pb(pass1+pass2), roche_ont(pass2),
roche_pb(pass2), ug_pb(pass2). ug_ont already fixed in commit 9426248."

echo "=== GIT PUSH ==="
git push origin feat/modular-hybrid-workflows

echo "=== DONE ==="
git log --oneline -3

