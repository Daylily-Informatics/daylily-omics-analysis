#!/bin/bash
set -x
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

# Status
git status --short workflow/rules/

# Check if changes exist
if ! git diff --quiet workflow/rules/sent_hybrid_ug_ont_modular.smk workflow/rules/sent_hybrid_ug_pb_modular.smk workflow/rules/sent_hybrid_ilmn_ont_modular.smk workflow/rules/sent_hybrid_ilmn_pb_modular.smk workflow/rules/sent_hybrid_roche_ont_modular.smk workflow/rules/sent_hybrid_roche_pb_modular.smk 2>/dev/null; then
    echo "Changes found"
    git add workflow/rules/sent_hybrid_ug_ont_modular.smk
    git add workflow/rules/sent_hybrid_ug_pb_modular.smk
    git add workflow/rules/sent_hybrid_ilmn_ont_modular.smk
    git add workflow/rules/sent_hybrid_ilmn_pb_modular.smk
    git add workflow/rules/sent_hybrid_roche_ont_modular.smk
    git add workflow/rules/sent_hybrid_roche_pb_modular.smk
    git commit -m "fix: comprehensive Pass1 + Transfer sample name fix for hybrid workflows"
    git push origin feat/modular-hybrid-workflows
else
    echo "No changes to commit"
fi

git log -1 --oneline

