#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

git add workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk \
       workflow/rules/sent_hybrid_ilmn_ont_modular.smk

git commit -m 'fix(hiom/hiomr): unify SM tags via cluster_sample --replace_rg for both LR and SR readgroups

Root cause: DNAscope creates two-sample VCFs when input readgroups have
different SM tags. Only ONT readgroups were getting --replace_rg to set SM,
while SR BAM readgroups kept their original SM:hg003. This caused
DNAModelApply to fail with "model only supports single sample VCF".

Fix: All rules now use {params.cluster_sample} (from ret_sample) for SM
in --replace_rg args instead of {config[sentdhio][sample_sm]}. Rules with
both LR and SR inputs (pass1, mapq0_bed, stage3) now extract SR readgroup
IDs and build SR_RG_ARGS to replace SR SM tags too. Stage1 bwa mem -R and
SR alignment bwa mem -R also use cluster_sample.

This matches the sentieon-cli reference implementation which applies
replace_rg to ALL inputs (both LR and SR).'

echo "Commit done. Pushing..."
git push origin feat/modular-hybrid-workflows
echo "Push done."

