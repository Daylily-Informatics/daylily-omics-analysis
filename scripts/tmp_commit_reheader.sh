#!/bin/sh
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

git add workflow/rules/sent_hybrid_ilmn_ont_modular.smk
git add workflow/rules/sent_hybrid_ilmn_pb_modular.smk
git add workflow/rules/sent_hybrid_roche_ont_modular.smk
git add workflow/rules/sent_hybrid_roche_pb_modular.smk
git add workflow/rules/sent_hybrid_ug_pb_modular.smk

git commit -m "fix: reheader LR+stage3 BAMs in pass1/pass2 for single-sample VCFs"

echo "EXIT_CODE: $?"
git log --oneline -3
echo "PUSH_NOW"
git push origin feat/modular-hybrid-workflows
echo "PUSH_EXIT: $?"

