#!/usr/bin/env bash
set -euo pipefail

cd /Users/jmajor/projects/daylily/daylily-omics-analysis

echo "=== Adding and committing ==="
git add workflow/rules/sent_hybrid_ilmn_ont_modular.smk \
       workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk
git commit -m "fix: escape all Snakemake shell braces in HIOM workflows

- Double-brace all LR awk blocks (6 per file) to prevent Python format() errors
- Escape \${rgid} -> \${{rgid}} (20 in standard, 12 in refactored)
- Add config['sentdhio'] setdefault initialization to both files
- Fix \${timestamp} -> \${{timestamp}} on refactored stage1 rule"

echo "=== Pushing ==="
git push origin feat/modular-hybrid-workflows

echo "=== Done ==="

