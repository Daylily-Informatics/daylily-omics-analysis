#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

echo "=== Staging files ==="
git add workflow/rules/common.smk workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk
git status --short

echo "=== Committing ==="
git commit -m "feat: add chromosome-level sharding to sentdhiomr transfer rule for parallel execution"

echo "=== Pushing to feat/modular-hybrid-workflows ==="
git push origin feat/modular-hybrid-workflows

echo "=== Done ==="
git log --oneline -3

