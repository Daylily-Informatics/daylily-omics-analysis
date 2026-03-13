#!/usr/bin/env bash
set -euo pipefail

cd /Users/jmajor/projects/daylily/daylily-omics-analysis

git add \
  workflow/rules/sent_hybrid_roche_ont_modular.smk \
  workflow/rules/sent_hybrid_roche_pb_modular.smk \
  workflow/rules/sent_hybrid_ug_ont_modular.smk \
  workflow/rules/sent_hybrid_ug_pb_modular.smk

git commit -m "feat: add --replace_rg with LR:1 tag to remaining 4 modular hybrid workflows

Replace samtools reheader approach with sentieon driver --replace_rg
in pass1, mapq0, stage3, and pass2 rules for:
- sent_hybrid_roche_ont_modular.smk
- sent_hybrid_roche_pb_modular.smk
- sent_hybrid_ug_ont_modular.smk
- sent_hybrid_ug_pb_modular.smk

The LR:1 readgroup tag is critical for the hybrid.model to distinguish
long reads from short reads. Without it, indel precision drops from
~0.97 (CLI) to ~0.63 (modular). This matches the CLI behavior exactly.

Also removes temporary BAM creation/indexing/cleanup, improving
performance by avoiding full BAM copies."

git push origin feat/modular-hybrid-workflows

echo "=== Push complete ==="
git log --oneline -3

