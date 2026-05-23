# HG003 HIOMR And ONT Solo 1.0.21 Cluster Validation Ledger

## Summary

Validate a patched DayOA release on the running `hyb-hg003` cluster. The release under test is `1.0.21`, defined as `1.0.20` plus the focused `sentdhiomr` rule-env Python fix. Run fresh `day-clone -t 1.0.21` tmux workdirs for HIOMR HG003 5x ILMN + 5x ONT limited to chromosomes `4,5`, and ONT solo full HG003 from already staged manifests. Continue through tagged bugfix releases until both pipelines complete alignstats and SNV concordance, or a terminal blocker is recorded.

## Gate 0 Inventory

- Ledger path: `docs/plans/20260523T124908Z_hg003_hiomr_ont_1021_cluster_validation_ledger.md`
- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `main`
- Remote: `origin git@github.com:Daylily-Informatics/daylily-omics-analysis.git`
- Baseline status before ledger: `## main...origin/main`; dirty files were `tests/test_snakemake_parser_contracts.py` and `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk`.
- Baseline release: `1.0.20` at `d6586f09fd6232bd2dcb50b04d4e259a444e86db`, matching `origin/main`.
- Planned release tag: `1.0.21`, unless occupied before tagging.
- Local release checks required before tag: `python -m pytest -q tests/test_snakemake_parser_contracts.py`; `bash -n bin/day_run`; clean `git status --short --branch` after commit.
- Cluster: `hyb-hg003`, region `us-west-2`, profile `lsmc`; `pcluster describe-cluster` showed headnode `i-03f1a49bbc4e39d4b`, state `running`, compute fleet `RUNNING`.
- Headnode access rule: SSM/daylily-ec only; commands must use `bash -l -c`; no direct SSH or `pcluster ssh`.
- Headnode preflight evidence from `2026-05-23`: `id -un -> ubuntu`; `command -v day-clone -> /home/ubuntu/.local/bin/day-clone`; `command -v tmux -> /usr/bin/tmux`; `command -v squeue -> /opt/slurm/bin/squeue`.
- Current live queue before this ledger: `squeue -u ubuntu` empty.
- Existing failed ONT evidence: `/fsx/analysis_results/johnm/hg003a_ont_solo_fullcov_1020_concordance/daylily-omics-analysis` is exact `1.0.20`; `daylily.failed_run` exists; alignstats TSVs exist; `sent_snv_ont` failed with `DNAscope: Failed to open temp file /dev/shm/... No such file or directory`.
- Existing failed HIOMR evidence: `/fsx/analysis_results/johnm/hg003_hiomr_5x5x_1019_stdlibfix2/daylily-omics-analysis` is `1.0.19-dirty`; `sentdhiomr_hybrid_select` chr `5` and `6` logs show bare `python` resolved to `/home/ubuntu/miniconda3/bin/python` Python `3.13.13`; `$CONDA_PREFIX` pointed at the correct Snakemake rule env.
- HIOMR staged manifests:
  - samples: `/fsx/analysis_results/johnm/staged_manifests/hg003_hiomr_5x5x_from_envfix_1019/20260523T114000Z_samples.tsv`
  - units: `/fsx/analysis_results/johnm/staged_manifests/hg003_hiomr_5x5x_from_envfix_1019/20260523T114000Z_units.tsv`
  - row count: 2 lines each; sample `HG003`; unit `HIOGIAB5X5X`; ILMN FASTQs are HG003 5x downsampled R1/R2; ONT CRAM is `/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/HG003_5x.cleaned.cram`.
- ONT solo staged manifests:
  - samples: `/fsx/analysis_results/johnm/staged_manifests/remote_stage_20260522T203135Z_hg003_concordance_fsx_1019/20260523T113105Z_samples.tsv`
  - units: `/fsx/analysis_results/johnm/staged_manifests/remote_stage_20260522T203135Z_hg003_concordance_fsx_1019/20260523T113105Z_units.tsv`
  - row count: 2 lines each; sample `HG003-a`; unit `20260514-LH01106-0009-B23TVLGLT4`; ONT CRAM is `/fsx/data/staged_sample_data/remote_stage_20260522T203135Z/20260514-LH01106-0009-B23TVLGLT4_HG003-a-NOVASEQ-PF-gdna-20260514-ILMN-Altair-Run-3_HG003-a_0/HG003_30x.cleaned.cram`.
- No destructive AWS action is required or authorized.

## Rows

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| REL-001 | Release | Commit the current `1.0.20` plus `sentdhiomr` rule-env Python patch, pass focused tests, push, tag `1.0.21`, and push the tag. | IN_PROGRESS | feature_implementation | Gate 1 | orchestrator | Dirty patch scoped to `tests/test_snakemake_parser_contracts.py` and `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk`. | | |
| CLUSTER-001 | Cluster preflight | Verify `hyb-hg003` headnode, SSM/login-shell tooling, Slurm queue, and tmux hygiene before launching fresh sessions. | OPEN | feature_implementation | Gate 2 | orchestrator | Baseline pcluster and SSM inventory recorded in Gate 0. | | |
| HIOMR-001 | HIOMR dry-run | Launch fresh `day-clone -t 1.0.21 -d hg003_hiomr_chr4_5_1021_dryrun`, stage manifests, limit `sentdhiomr.hg38_broad_sentdhiomr_chrms` to `4,5`, and complete the planned dry-run. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| HIOMR-002 | HIOMR real run | Launch fresh `day-clone -t 1.0.21 -d hg003_hiomr_chr4_5_1021`, run real HIOMR chr `4,5`, and complete alignstats plus SNV concordance. | OPEN | feature_implementation | Gate 4 | Agent A | | | |
| ONT-001 | ONT dry-run | Launch fresh `day-clone -t 1.0.21 -d hg003a_ont_solo_fullcov_1021_dryrun`, stage manifests, and complete the planned ONT solo dry-run. | OPEN | feature_implementation | Gate 3 | Agent B | | | |
| ONT-002 | ONT real run | Launch fresh `day-clone -t 1.0.21 -d hg003a_ont_solo_fullcov_1021`, run real ONT solo, and complete alignstats plus SNV concordance. | OPEN | feature_implementation | Gate 4 | Agent B | | | |
| VERIFY-001 | Final acceptance | Verify both real runs have no `daylily.failed_run`, expected outputs exist, Slurm queue/controller state is clean, and every ledger row is terminal. | OPEN | contract_test | Gate 5 | orchestrator | | | |

## Command Contracts

HIOMR dry-run command:

```bash
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config dedupers=["dmd"] -p -j 100 -k -T 0 --rerun-triggers mtime -n
```

HIOMR real command:

```bash
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config dedupers=["dmd"] -p -j 100 -k -T 0 --rerun-triggers mtime
```

ONT solo dry-run command:

```bash
dy-r produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances -p -j 5 -k -T 0 --rerun-triggers mtime -n
```

ONT solo real command:

```bash
dy-r produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances -p -j 5 -k -T 0 --rerun-triggers mtime
```

