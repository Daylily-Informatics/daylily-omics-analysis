#!/bin/bash
set -e
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
echo "=== GIT STATUS ==="
git status --short
echo "=== GIT LOG ==="
git log --oneline -5
echo "=== GIT DIFF STAT ==="
git diff --stat
echo "=== CHECKING FOR SR_RG_ARGS ==="
grep -c SR_RG_ARGS workflow/rules/sent_hybrid_ilmn_ont_modular.smk || echo "HIOM: 0 occurrences (GOOD)"
grep -c SR_RG_ARGS workflow/rules/sent_hybrid_ilmn_pb_modular.smk || echo "HIPB: 0 occurrences (GOOD)"

