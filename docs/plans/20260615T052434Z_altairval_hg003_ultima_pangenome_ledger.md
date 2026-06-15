# Altairval HG003 Ultima Pangenome Ledger

## Objective

Run the staged HG003 Ultima data from `s3://lsmc-ssf-*` on the `altairval` cluster through the Sentieon Ultima pangenome pipeline, then run `produce_snv_concordances` for the dataset. Also describe the Ultima data found in the staged S3 location so the HG003 run is a controlled pilot before the complete 23andMe Ultima dataset.

## Gate 0 Inventory

| Check | Result |
| --- | --- |
| Ledger path | `docs/plans/20260615T052434Z_altairval_hg003_ultima_pangenome_ledger.md` |
| Local orchestration repo | `/Users/jmajor/projects/lsmc/daylily-omics-analysis` |
| Cluster repo | `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster` |
| AWS profile / region | `lsmc` / `us-west-2` |
| Target cluster | `altairval` |
| Source S3 scope | `s3://lsmc-ssf-*`; current visible matching bucket is `s3://lsmc-ssf-sequencing-data` |
| Staged Ultima prefix under review | `s3://lsmc-ssf-sequencing-data/staged_external_data/23andMePilot/ultima/` |
| Raw Ultima run prefix also observed | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN602221/2026/602221-20260417_2346/` |
| Staged HG003 source prefix | `s3://lsmc-ssf-sequencing-data/staged_external_data/23andMePilot/ultima/40x/HG003/` |
| Staged HG003 mounted path | `s3://.../40x/HG003/` -> `/fsx/staging/hg003_ultima_40x/` via read-only DRA `dra-0376dcdbf8accb13e` |
| HG003 CRAM manifest path | `/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram` |
| Prior non-authoritative failed attempt | June 9 dry-run used `/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_3x.cleaned.cram`; it failed because that control-data path was missing. This run must use the staged `lsmc-ssf` data scope instead. |
| DayOA command contract | Use `ubuntu` on the headnode in a persistent tmux login shell; run `source dyoainit`, then `dy-a slurm hg38_broad`, then `dy-r ...`; never invoke raw `snakemake`. |
| Destructive actions | None approved and none planned. Do not delete, cancel, requeue, drain, resume, restart Slurm, or modify AWS resources unless separately approved. |

## Working Assumptions

- `profile=lsmc` and `region=us-west-2` are used because current Altair/LSMC evidence and the visible `lsmc-ssf-*` bucket are in that account/region.
- The intended DayOA target for Ultima pangenome is `produce_pangenome_ug_vcf`; the concordance target is `produce_snv_concordances`.
- HG003 should be selected from the staged 23andMe Pilot Ultima prefix if its CRAM/CRAI and supporting files are present and compatible with DayOA manifests.
- Do not substitute a smaller control-data fixture, generated alternate path, or service-side discovery fallback if exact staged HG003 inputs are missing.

## Ledger Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| G0-001 | Inventory | Record local instructions, prior context, repo state, AWS profile/region, cluster, and source scope before launch. | PASS | legitimate_safety_handling | Gate 0 | orchestrator | Instructions read from repo/global AGENTS files and DayOA run contract; prior June 9 control-data dry-run identified as non-authoritative for this request; `altairval` cluster status is `CREATE_COMPLETE` and fleet is `RUNNING`; Daylily EC local CLI is `10.0.34`. |  | Gate 0 inventory complete. |
| DATA-001 | S3 staged data | Describe the Ultima staged data under `s3://lsmc-ssf-sequencing-data/staged_external_data/23andMePilot/ultima/`, including sample count, per-sample file classes, HG003-specific files, and total sizes. | PASS | feature_implementation | Gate 1 | orchestrator | Inventory artifacts: `docs/plans/20260615T052434Z_altairval_hg003_ultima_s3_inventory.py`, `.json`, and `.tsv`. Staged prefix has 4,256 objects, 17,959,050,828,791 bytes, 96 top-level sample-like branches including `reference_genome`, and 95 biological samples. |  | Staged data described in the inventory section below. |
| DATA-002 | HG003 selection | Confirm exact HG003 staged inputs to use for DayOA, including CRAM and CRAI paths and whether existing non-CRAM VCF/gVCF/call artifacts are inputs or only descriptive side products. | PASS | feature_implementation | Gate 1 | orchestrator | HG003 branch has 27 objects, 67,745,431,536 bytes, one CRAM `cram/HG003_40X.cram`, one CRAI `cram/HG003_40X.cram.crai`, EDV VCF/gVCF artifacts, and ancillary CNV/segdup/STR/PGx/HLA/QC files. DayOA `sentieon_pangenome_ug` consumes the CRAM/CRAI; existing EDV and other call files are descriptive side products, not inputs to this pangenome target. |  | HG003 CRAM/CRAI selected. |
| ASSET-001 | Sentieon assets | Verify the exact Sentieon code/model and supporting pangenome assets used by the live Ultima pangenome run. | PASS_WITH_CAVEAT | contract_test | Gate 5 | orchestrator | Active log and config show Sentieon env `sentieon-genomics-202503.03` / `sentieon-202503.03-0`, model `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bundles/SentieonUltimaPangenomeRealignWGS1.3.bundle`, graph files `hprc-v2.0-mc-grch38.gbz` and `.hapl`, `--pop_vcf /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz`, canonical bed `hg38_canonical.bed`, and `--dbsnp Homo_sapiens_assembly38.dbsnp138.vcf.gz`. Targeted read-only inventory shows visible Sentieon envs `202503.02` and `202503.03`, visible Ultima pangenome bundles `WGS1.0` and active `WGS1.3`, and visible pangenome population VCFs `pop-v20-20260528.vcf.gz` and `pop-v20g41-20251216.vcf.gz`. |  | Uses newest visible Sentieon env and active Ultima pangenome model; does not literally pass every visible population/support VCF. |
| CLUSTER-001 | Altairval preflight | Verify `altairval` is reachable, headnode runs as `ubuntu`, login shell/tmux/day-clone/squeue are available, and Slurm status can be read. | PASS | legitimate_safety_handling | Gate 2 | orchestrator | `dyec cluster describe` reports `clusterStatus=CREATE_COMPLETE`, `computeFleetStatus=RUNNING`, scheduler `slurm`, headnode `i-05b2743c3c3fffa93` running at `10.0.0.157`. Headnode preflight found `ubuntu`, `tmux`, `day-clone`, `squeue`, and exact HG003 CRAM/CRAI visibility. |  | Cluster preflight complete. |
| MANIFEST-001 | DayOA manifest | Create or verify exact DayOA `samples.tsv` and `units.tsv` for the staged HG003 Ultima CRAM, without inferred defaults or fallback control-data paths. | PASS | feature_implementation | Gate 3 | orchestrator | Local manifests written: `docs/plans/20260615T052434Z_altairval_hg003_ultima_samples.tsv` and `docs/plans/20260615T052434Z_altairval_hg003_ultima_units.tsv`; units row sets `ULTIMA_CRAM=/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram`, `ULTIMA_CRAM_ALIGNER=ug`, `ULTIMA_CRAM_SNV_CALLER=ug`, and `ULTIMA_SUBSAMPLE_PCT=na`. Manifest was copied into the remote clone at `/fsx/analysis_results/ubuntu/altair_hg003_ultima_pg_20260615T052434Z/daylily-omics-analysis/config/`. |  | Exact staged HG003 manifest in use. |
| MOUNT-001 | Staging mount | Create a read-only FSx DRA for the exact staged HG003 Ultima prefix so DayOA can validate a local CRAM path. | PASS | feature_implementation | Gate 2 | orchestrator | DRA `dra-0376dcdbf8accb13e`, source `s3://lsmc-ssf-sequencing-data/staged_external_data/23andMePilot/ultima/40x/HG003/`, headnode path `/fsx/staging/hg003_ultima_40x/`, read-only, no auto-export/writeback, lifecycle `AVAILABLE`. Exact mounted inputs visible: `/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram` and `.cram.crai`. |  | Mount available; no broader staged tree was mounted for this run. |
| SCRIPT-001 | Launch helpers | Preserve exact SSM/tmux helper scripts used for headnode preflight, dry-run launch, status capture, live submission, and narrow status polling. | PASS | legitimate_safety_handling | Gate 2 | orchestrator | Added `20260615T052434Z_altairval_hg003_ultima_ssm_preflight.py`, `..._ssm_launch_dryrun.py`, `..._ssm_capture.py`, `..._ssm_send_live.py`, and `..._ssm_status.py`; `python -m py_compile` succeeded for the status helper and previously succeeded for the first four scripts. |  | Helper scripts ready. |
| DRYRUN-001 | DayOA dry-run | In a persistent `ubuntu` tmux pane on `altairval`, run a `dy-r` dry-run for `produce_pangenome_ug_vcf` with `hg38_broad`. | PASS | contract_test | Gate 4 | orchestrator | Tmux session `altair_hg003_ultima_pg_20260615T052434Z`; `source dyoainit --skip-project-check`, `dy-a slurm hg38_broad`, then `dy-r produce_pangenome_ug_vcf -p -j 150 -k -T 0 --rerun-triggers mtime -n`; marker `__DAYOA_STAGE__=dry_run_done 2026-06-15T05:54:54+00:00`, `RETURN CODE: 0`; DAG planned 6 jobs including `pre_prep_ultima_cram` and `sentieon_pangenome_ug`. |  | Dry-run passed. |
| LIVE-001 | Pangenome run | Launch the live Sentieon Ultima pangenome workflow for HG003 through `dy-r`, from the verified manifest. | IN_PROGRESS | feature_implementation | Gate 5 | orchestrator | Live command: `dy-r produce_pangenome_ug_vcf -p -j 150 -k -T 0 --rerun-triggers mtime`; marker `__DAYOA_STAGE__=live_run_start 2026-06-15T05:55:08+00:00`. `pre_prep_ultima_cram` job `48` completed and created symlinks to the mounted CRAM/CRAI. `sentieon_pangenome_ug` is Slurm job `49`; earlier status at `2026-06-15T07:39:16+00:00` was `RUNNING` on `i128nvme-dy-price128nvme-1` with DNAscope at `progress 50% @chr9:22000001`, but that is only the last sampled progress point from the first attempt, not a confirmed failure location. Latest status at `2026-06-15T08:29:42+00:00`: job `49` is still `RUNNING`, `Restarts=1`, current start time `2026-06-15T07:52:35`, current runtime 37:07, node `i384nvme-dy-price384nvme-1`, `ReqTRES=cpu=128,mem=200000M,node=1,billing=128`, `AllocTRES=cpu=384,mem=200000M,node=1,billing=128`, `CPUs/Task=128`. First attempt likely ran from about `2026-06-15T06:03:35+00:00` to the requeue around `2026-06-15T07:51:13+00:00` based on the earlier `squeue` runtime and current `scontrol` times. Current rule log was rewritten for a new TMPDIR `/scratch/pangenome_ug_tmp_20260615075244_27801`; current attempt completed pgutil extract (`Total : 1480.57s`, tmp 111101 MB), loaded GBZ/hapl, assigned 195 reference paths, read kmer counts, estimated kmer coverage, and is building GBWT. |  | Caller running after one Slurm restart; first-attempt failure reason not yet visible from current job logs. |
| CONC-001 | Concordance run | Run or continue `produce_snv_concordances` for the same HG003 dataset after pangenome outputs are available. | DEFERRED | feature_implementation | Gate 5 | orchestrator | User narrowed the current execution to watching the mount and running the pangenome Sentieon Ultima caller from the mounted HG003 CRAM/CRAI. Concordance remains planned after pangenome output exists, but is not part of the active live command. |  | Deferred by scope update. |
| STATUS-001 | Evidence/status | Capture tmux session name, exact DayOA command, Slurm queue snapshot, controller process status, and output/concordance evidence. | IN_PROGRESS | contract_test | Gate 6 | orchestrator | Tmux session `altair_hg003_ultima_pg_20260615T052434Z`; tmux log `/home/ubuntu/daylily-runs/altair_hg003_ultima_pg_20260615T052434Z/tmux.log`; remote clone `/fsx/analysis_results/ubuntu/altair_hg003_ultima_pg_20260615T052434Z/daylily-omics-analysis`. Latest poll at `2026-06-15T08:23:06+00:00` captured Slurm job `49` running on `i384nvme-dy-price384nvme-1`; `scontrol` reports `Restarts=1`, `NumCPUs=384`, `CPUs/Task=128`, and requested `cpu=128,mem=200000M`. No final VCF/TBI or `gatheredall.pangenome_ug` yet. Slurm stdout is empty; rule-specific Slurm stderr is 16K and contains the generated job script/Snakemake header, including `threads: 128`, `vcpu=128`, `mem_mb=200000`, active model and pangenome support paths, and no runtime failure signal beyond template `ERROR:` strings embedded in the script body. Current Sentieon rule log is 11K and shows current attempt through GBZ/hapl loading and kmer count reading. |  | Monitoring active. |

## Scope Update

After the DRA safety pause, the current live scope is intentionally narrowed to the mounted HG003 CRAM/CRAI and the Sentieon Ultima pangenome caller only. `produce_snv_concordances` remains a downstream step after pangenome output exists, but it was not included in the live command launched for this safety-narrowed pass.

## Actual DayOA Command Shape

Dry-run first:

```bash
source dyoainit
dy-a slurm hg38_broad
dy-r produce_pangenome_ug_vcf -p -j 150 -k -T 0 --rerun-triggers mtime -n
```

Live run after dry-run success:

```bash
dy-r produce_pangenome_ug_vcf -p -j 150 -k -T 0 --rerun-triggers mtime
```

These commands ran in tmux session `altair_hg003_ultima_pg_20260615T052434Z` on `altairval` as `ubuntu`, through `dy-r` rather than a direct Snakemake invocation.

## Staged Ultima Inventory Summary

Reproducible inventory command:

```bash
AWS_PROFILE=lsmc AWS_DEFAULT_REGION=us-west-2 python docs/plans/20260615T052434Z_altairval_hg003_ultima_s3_inventory.py
```

Observed under `s3://lsmc-ssf-sequencing-data/staged_external_data/23andMePilot/ultima/`:

- 4,256 total S3 objects and 17,959,050,828,791 bytes.
- 96 top-level sample-like branches, including `reference_genome`; 95 branches are biological sample data.
- Biological sample sizes range from HG003 at 67,745,431,536 bytes to 328,360,241,761 bytes.
- CRAM distribution: HG003 has one staged CRAM; 94 non-HG003 biological samples have two staged CRAMs each.
- File-class counts across the staged prefix: 189 CRAM, 189 CRAI, 570 EDV VCF-side objects, 190 EDV gVCF-side objects, 190 CNV, 756 segdup, 378 STR, 189 PGx, 189 HLA, 189 QC, 566 individual-run CSVs, and 661 other objects.
- `reference_genome/` contains GRCh38 no-alt analysis set FASTA support files: `.fna`, `.dict`, and `.fna.fai`.

HG003 staged branch:

- Prefix: `s3://lsmc-ssf-sequencing-data/staged_external_data/23andMePilot/ultima/40x/HG003/`.
- Objects: 27; total bytes: 67,745,431,536.
- Input CRAM/CRAI selected for DayOA: `cram/HG003_40X.cram` at 65,489,595,215 bytes and `cram/HG003_40X.cram.crai` at 2,787,537 bytes, both last modified `2026-06-09T00:42:06Z`.
- Side products present but not used as pangenome inputs: EDV VCF/gVCF, chrM EDV VCF/gVCF, CNV VCF, segdup BED/VCF, STR VCF, PGx TSV, HLA text, sorter stats CSV, and six individual-run CSVs.
