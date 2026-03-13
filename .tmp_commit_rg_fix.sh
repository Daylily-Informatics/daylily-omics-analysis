#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

git add workflow/rules/sent_hybrid_ilmn_ont_modular.smk \
        workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk

git commit -m "fix: escape tab chars in bwa mem -R @RG strings (\\t → \\\\t)

sentieon bwa mem expects literal backslash-t in the -R readgroup string,
not actual tab bytes. In a Snakemake shell block (Python string), \\t
becomes a literal tab, but \\\\t becomes \\t which bwa interprets correctly.

Error was: [E::bwa_set_rg] the read group line contained literal <tab>
characters -- replace with escaped tabs: \\t

Fixed in both sent_hybrid_ilmn_ont_modular.smk and .refactored.smk
(sr_align and stage1 bwa mem calls)."

git push origin feat/modular-hybrid-workflows

