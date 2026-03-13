#!/bin/bash
set -e
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

# Add files
git add workflow/rules/sent_hybrid_*_modular.smk

# Commit with message
git commit -m "fix: comprehensive multi-sample VCF fix for hybrid modular workflows

- Pass1 fix: Reheader input CRAM/BAM files to use cluster_sample name BEFORE DNAscope
- Transfer fix: Use old->new format for bcftools reheader (echo -e 'old\tnew')
- Applied to all 6 hybrid modular workflows

Root cause: DNAscope creates multi-sample VCF when input files have different SM tags"

# Push
git push origin feat/modular-hybrid-workflows

echo "=== Commit and push complete ==="
git log -1 --oneline

