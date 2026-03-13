#!/bin/bash
set -euo pipefail

echo "=== COMMIT AND PUSH ==="
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

git add workflow/rules/sent_hybrid_ug_ont.smk workflow/rules/sent_hybrid_ug_pb.smk
git commit -m "fix: avoid double-gzip in sort_index_chunk_vcf for CLI UG+ONT/PB

sentieon-cli produces .vcf.gz (bgzipped) output. The sort_index rule
was copying .vcf.gz to .sort.vcf then bgzipping again, creating a
double-gzipped file that tabix could not parse.

Now copies .vcf.gz directly to .sort.vcf.gz and indexes it."

git push origin feat/modular-hybrid-workflows

echo ""
echo "=== DONE ==="
git log --oneline -3

