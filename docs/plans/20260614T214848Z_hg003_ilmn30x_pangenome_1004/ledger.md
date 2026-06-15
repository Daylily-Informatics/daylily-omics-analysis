# HG003 ILMN 30x Sentieon Pangenome 10.0.4 Ledger

Created: 2026-06-14T21:48:48Z

## Objective

Run HG003 30x Illumina data through two `day-clone -t 10.0.4` DayOA Sentieon pangenome analysis directories on dyecX4:

- current ILMN pangenome model: `SentieonIlluminaPangenomeRealignWGS1.2.bundle`
- predecessor ILMN pangenome model: `SentieonIlluminaPangenomeRealignWGS1.0.bundle`

Report for each experiment:

- `aligstats` WGS coverage metrics, if emitted by the 10.0.4 pangenome pipeline
- separate Sentieon BWA alignment `aligstats` WGS coverage metrics using Doppelmark (`dppl`, normalized by 10.0.4 to canonical `dmd`)
- `produce_snv_concordance` F-scores for `altair` reportable regions
- `produce_snv_concordance` F-scores for `giabHC`

## Gate 0 Inventory

| Check | Evidence |
| --- | --- |
| DayOA repo | `/Users/jmajor/projects/lsmc/daylily-omics-analysis` |
| DayOA local branch/status before edits | `## jem-dev...origin/jem-dev`; pre-existing modifications in `tests/test_multiqc_qc_targets.py`, `tests/test_multiqc_sample_identifiers.py`, `workflow/rules/vep.smk`, and untracked local artifacts. |
| New files owned by this run | `docs/plans/20260614T214848Z_hg003_ilmn30x_pangenome_1004/{ledger.md,samples.tsv,units.tsv}` |
| Requested tag | `10.0.4`; `git cat-file -t 10.0.4 -> tag`; target commit `b0e35b9 Add SMN12 orthogonal caller workflows`. |
| Cluster | dyecX4 |
| AWS profile/region | `lsmc` / `us-west-2`, from prior durable acceptance ledger and verified by `daylily-ec cluster-info`. |
| Live cluster state | `dyecX4 CREATE_COMPLETE` in `us-west-2`. |
| Input data | Full HG003 30x FASTQs from `giab_30x_hg38_analysis_manifest.csv`; original manifest paths were absent on dyecX4, so generated `units.tsv` uses proven FSx files under `/fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/`; `SUBSAMPLE_PCT=na`. |
| Truth root | `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/` |
| 10.0.4 current pangenome config | `sentieon_pangenome_sr.model=/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.2.bundle`; `pop_vcf=/fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20-20260528.vcf.gz`. |
| 10.0.4 prior-model support | No `sentieon_pangenome_sr_model_mode` or `prior_model` key in tag `10.0.4`; prior run requires explicit per-analysis `config/rule_config.yaml` edit after clone. |
| Alignstats risk | In tag `10.0.4`, `GRAPH_ONLY_PANGENOME_ALIGNERS={"pangenome_sr","pangenome_ug"}` and `QC_CRAM_ALIGNERS` excludes them; pangenome short-read rule emits VCF/log/benchmark outputs, not a BAM/CRAM consumed by `produce_alignstats`. |
| Asset preflight | `ssm_asset_check.py` verified model files, population VCFs, `altair-v1.1`, and `giabHC`; `ssm_find_hg003_fastqs.py` found the full HG003 30x FASTQs now used in `units.tsv`. |

## Execution Rows

| ID | Scope | Status | Evidence | Terminal Note |
| --- | --- | --- | --- | --- |
| RUN-001 | Launch current-model `10.0.4` clone and run pangenome VCF/concordance. | SUCCESS | Analysis dir `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/daylily-omics-analysis`; tmux `hg003_pg_current_1004_220039`; pangenome VCF `520192555` bytes with `.tbi` `1799286` bytes; live concordance rerun marker `__DAYOA_STAGE__=rerun_concordance_done label=current rc=0` at 2026-06-15T01:56:03Z; post-live final dry-run marker `__POST_LIVE_FINAL_DRYRUN_RC__=current pg=0 alignstats=0` at 2026-06-15T02:58:17Z. | Initial RTG ROI vcfeval jobs OOMed. Recovery used patched RTG memory and parser directory creation; final dry-run reports all requested pangenome/concordance files present and up to date. |
| RUN-002 | Launch prior-model `10.0.4` clone, edit generated config to predecessor model/pop VCF, and run pangenome VCF/concordance. | SUCCESS | Analysis dir `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/daylily-omics-analysis`; tmux `hg003_pg_prior_1004_220039`; pangenome VCF `623731699` bytes with `.tbi` `1825615` bytes; recovery parse marker `__DAYOA_STAGE__=prior_altair_parse_done rc=0` at 2026-06-15T02:55:46Z; post-live final dry-run marker `__POST_LIVE_FINAL_DRYRUN_RC__=prior pg=0 alignstats=0` at 2026-06-15T02:58:17Z. | Initial RTG ROI vcfeval jobs OOMed and prior-model sanitized ROI parse needed directory creation. Recovery used patched RTG memory, parser directory creation, and final dry-run reports all requested pangenome/concordance files present and up to date. |
| QC-001 | Report alignstats WGS coverage metrics for current model. | SUCCESS | User clarified to run a separate Sentieon BWA alignment for `produce_alignstats`; 10.0.4 normalizes `dppl` to `dmd`; live recovery marker `__RECOVERY_ALIGNSTATS_LIVE_RC__=0` at 2026-06-15T02:47:34Z; `other_reports/alignstats_combo_mqc.tsv` and `other_reports/alignstats_gs_mqc.tsv` are each `6593` bytes; `results/day/hg38_broad/logs/produce_alignstats.done` exists. | Initial target wrapper failed after heavy alignstats outputs existed because the active checkout lacked the `produce_alignstats.done` output wrapper. Recovery copied the fixed wrapper into the active checkout and reran through `dy-r`. |
| QC-002 | Report alignstats WGS coverage metrics for prior model. | SUCCESS | User clarified to run a separate Sentieon BWA alignment for `produce_alignstats`; 10.0.4 normalizes `dppl` to `dmd`; live recovery marker `__RECOVERY_ALIGNSTATS_LIVE_RC__=0` at 2026-06-15T02:47:34Z; `other_reports/alignstats_combo_mqc.tsv` and `other_reports/alignstats_gs_mqc.tsv` are each `6593` bytes; `results/day/hg38_broad/logs/produce_alignstats.done` exists. | Initial target wrapper failed after heavy alignstats outputs existed because the active checkout lacked the `produce_alignstats.done` output wrapper. Recovery copied the fixed wrapper into the active checkout and reran through `dy-r`. |
| CONC-001 | Report current-model F-scores for altair reportable and giabHC ROIs. | SUCCESS | `results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv` exists, `17028` bytes, mtime 2026-06-15T01:55:54Z; final dry-run reports pangenome/concordance up to date. | Current-model altair-v1.1 examples from the MQC file: SNPts F-score `0.967521718487341`; SNPtv F-score `0.9609936875097446`. |
| CONC-002 | Report prior-model F-scores for altair reportable and giabHC ROIs. | SUCCESS | `results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv` exists, `16926` bytes, mtime 2026-06-15T02:55:37Z; final dry-run reports pangenome/concordance up to date. | Prior-model altair-v1.1 examples from the MQC file: SNPts F-score `0.9681805929672015`; SNPtv F-score `0.961623078953895`. |

## Planned Launch Commands

Current-model command after `day-clone -t 10.0.4` and DayOA activation:

```bash
dy-r produce_pangenome_sr_vcf produce_snv_concordances -p -j 150 -k -T 0 --rerun-triggers mtime --config 'aligners=["pangenome_sr"]' 'snv_callers=["sentpg"]'
```

Prior-model command is the same after replacing the generated `sentieon_pangenome_sr.model` and `sentieon_pangenome_sr.pop_vcf` values in that analysis directory.

Separate Sentieon BWA/Doppelmark alignstats command after DayOA activation:

```bash
dy-r produce_sent_align produce_dmd_dedup_cram produce_alignstats -p -j 150 -k -T 0 --rerun-triggers mtime --config 'aligners=["sent"]' 'dedupers=["dppl"]'
```

## Execution Notes

- 2026-06-14T22:07Z: Initial current-model launch failed before clone due launcher bug: `RUN_DIR` was not exported for remote manifest decode. Fixed `ssm_launch_experiment.py`; no analysis directory had been created by that failed attempt.
- 2026-06-14T22:10Z: Current clone setup initially failed under global `set -u` at `dy-a slurm hg38_broad` (`bash: $3: unbound variable`). Launcher changed to avoid global nounset around DayOA activation.
- 2026-06-14T22:12Z: Current clone setup then failed under global `set -e` because DayOA activation/deactivation cleanup is not `set -e` safe. Launcher changed to avoid global errexit and check critical command return codes explicitly.
- 2026-06-14T22:13Z: Current dry-runs passed. The pangenome dry-run emitted shell recipe lines containing literal `ERROR:` strings from the rule body; command return code was zero and the `pangenome_dry_run_done` marker was reached.
- 2026-06-14T22:14Z: Prior clone dry-runs passed after per-clone patch to `SentieonIlluminaPangenomeRealignWGS1.0.bundle` and `pop-v20g41-20251216.vcf.gz`.
- 2026-06-14T22:15Z: Live pangenome stages started in both tmux sessions; Slurm showed two `sentieon` jobs in `CF` (`5528`, `5529`).
- 2026-06-14T22:46Z: Re-checked active current-model clone. `SentieonIlluminaPangenomeRealignWGS1.2.bundle` is configured with `pop-v20-20260528.vcf.gz`; that VCF header has `##SentieonVcfID=population-hprc-v2.0-20260528`. Prior VCF `pop-v20g41-20251216.vcf.gz` has `##SentieonVcfID=population-hprc-v2.0+gnomad-v4.1.0-20251216` and is used only for the predecessor-model clone.
- 2026-06-14T23:13Z: Both pangenome VCFs were written. Current VCF size `520192555` bytes; prior VCF size `623731699` bytes. RTG `rtg_vcfeval_roi` concordance jobs were submitted for both clones (`5546`-`5557`) and were in `CF`; no `summary.txt` or `other_reports` output yet.
- 2026-06-14T23:18Z: Current pangenome/concordance `dy-r` returned `rc=1`; RTG logs end with the RTG Java process `Killed`, consistent with OOM under high ROI concurrency. Current alignstats stage then started and submitted `sentieon_bwa_sort` job `5562`.
- 2026-06-14T23:23Z: Prior pangenome/concordance `dy-r` returned `rc=1`; partial summaries were present for `altair-v1.1`, `clinvar_genes`, `giabHC_x_clinvar_genes`, and `hg38`, but not all requested/final report outputs. Prior alignstats stage then started and submitted `sentieon_bwa_sort` job `5563`.
- 2026-06-15T00:06Z: Patched both active clone configs to request more memory for RTG concordance: `rtg_vcfeval.mem_mb=500000`, `rtg_vcfeval.parse_mem_mb=64000`, `rtg_vcfeval.partition_other=i384nvme,i192hugenvme,i192`.
- 2026-06-15T00:08Z: Sentieon BWA/Doppelmark CRAMs exist in both clones, but `alignstats` failed before JSON output. Patched both active clone configs to request `alignstats.mem_mb=160000` and `alignstats.partition=i384nvme,i192nvme,i128`.
- 2026-06-15T01:47Z: Queued patched reruns in the existing tmux sessions. Dry-runs passed for both clones. Current dry-run needs 6 RTG ROI jobs and 2 alignstats jobs; prior dry-run needs 2 RTG ROI jobs and 2 alignstats jobs. Live concordance rerun submitted RTG jobs with `mem_mb=500000`; Slurm jobs `5572`-`5578` were in `CF` and `5579` was pending for resources.
- 2026-06-15T01:56Z: Patched concordance reruns completed for both clones (`rc=0`).
- 2026-06-15T02:47Z: Separate Sentieon BWA/Doppelmark alignstats recovery completed for both clones (`__RECOVERY_ALIGNSTATS_LIVE_RC__=0`); `produce_alignstats.done` exists in both analysis directories.
- 2026-06-15T02:55Z: Forced prior-model Altair parse completed (`dry_rc=0 rc=0`) after creating the missing sanitized ROI work directory `_altair-v1_1`; the top-level prior `giab_concordance_mqc.tsv` now contains populated `altair-v1.1` class rows.
- 2026-06-15T02:58Z: Final dry-runs reported `pg=0 alignstats=0` for both clones.
- 2026-06-15T03:05Z: Final SSM extraction found no Slurm jobs for `ubuntu` and confirmed both top-level concordance TSVs and both alignstats TSVs were present.

## Final Metric Summary

### Alignstats `sent.dmd` WGS Coverage

Both clones use the same separate Sentieon BWA + Doppelmark alignment path for the requested alignstats metrics.

| Metric | Current model | Prior model |
| --- | ---: | ---: |
| WgsCoverageMean | 32.224574 | 32.224574 |
| WgsCoverageMedian | 33 | 33 |
| WgsCoverageStandardDeviation | 417.549146 | 417.549146 |
| WgsCoverageBases1Pct | 94.104365 | 94.104365 |
| WgsCoverageBases10Pct | 91.915417 | 91.915417 |
| WgsCoverageBases20Pct | 84.748962 | 84.748962 |
| WgsCoverageBases30Pct | 64.092102 | 64.092102 |
| WgsAlignedReads | 719025987 | 719025987 |
| WgsAlignedReadsPct | 99.624008 | 99.624008 |
| WgsCalculatedAlignedReads | 694943424 | 694943424 |
| WgsCovDuplicateReads | 24082563 | 24082563 |
| WgsCovDuplicateReadsPct | 3.336738 | 3.336738 |
| MappedReads | 721739668 | 721739668 |
| MappedReadsPct | 100.0 | 100.0 |

### `produce_snv_concordance` All-Variant F-scores

| Model | ROI | All F-score | TP | FP | FN |
| --- | --- | ---: | ---: | ---: | ---: |
| Current `SentieonIlluminaPangenomeRealignWGS1.2.bundle` | altair-v1.1 | 0.9547873167999502 | 444918.0 | 31293.0 | 10844.0 |
| Current `SentieonIlluminaPangenomeRealignWGS1.2.bundle` | giabHC | 0.9939747222460159 | 3788725.0 | 2746.0 | 43187.0 |
| Prior `SentieonIlluminaPangenomeRealignWGS1.0.bundle` | altair-v1.1 | 0.9555739019621946 | 445038.0 | 30655.0 | 10726.0 |
| Prior `SentieonIlluminaPangenomeRealignWGS1.0.bundle` | giabHC | 0.9942140957701462 | 3789967.0 | 2165.0 | 41947.0 |
- 2026-06-15T02:45Z: Re-assessed remaining failures. Current and prior pangenome/concordance dry-runs had already reached `RC=0`, but the active analysis checkouts still lacked the local `produce_alignstats.done` wrapper fix. Copied `workflow/rules/alignstats_compile.smk` into both active analysis checkouts using the DYEC SSM helper path, together with the already-applied `alignstats.smk`, `rtg_vcfeval.smk`, and parser fixes.
- 2026-06-15T02:46Z: Verified active clone recovery config: `alignstats.mem_mb=250000`, `rtg_vcfeval.mem_mb=650000`, `rtg_vcfeval.parse_mem_mb=128000`, `rtg_vcfeval.partition=i384nvme,i192hugenvme`, `rtg_vcfeval.partition_other=i384nvme,i192hugenvme`, direct RTG memory resource use with no fallback, parser creates sanitized ROI intermediate directories, and `produce_alignstats` has `done=f"{MDIR}logs/produce_alignstats.done"`.
- 2026-06-15T02:47Z: Live `produce_sent_align produce_dmd_dedup_cram produce_alignstats` recovery reran in both tmux sessions through `dy-r` without `-n`; both returned `__RECOVERY_ALIGNSTATS_LIVE_RC__=0`.
- 2026-06-15T02:48Z: Final current/prior dry-runs for `produce_pangenome_sr_vcf produce_snv_concordances` and `produce_sent_align produce_dmd_dedup_cram produce_alignstats` returned `RC=0` with "Nothing to be done" for both analyses.
- 2026-06-15T02:49Z: A queued prior-model `prior_altair_parse` live recovery command ran after the dry-run markers. It submitted six `parse_vcfeval_summary_roi` jobs with `--mem=128000` on `i384nvme,i192hugenvme`; all completed and the controller returned `__DAYOA_STAGE__=prior_altair_parse_done rc=0` at 2026-06-15T02:55:46Z.
- 2026-06-15T02:58Z: Post-live final dry-runs after the prior parse recovery returned `__POST_LIVE_FINAL_DRYRUN_RC__=current pg=0 alignstats=0` and `__POST_LIVE_FINAL_DRYRUN_RC__=prior pg=0 alignstats=0`; `squeue -u ubuntu` was empty.

## Recovery Changes Applied

These recovery changes were applied to local DayOA source and copied into the two active 10.0.4 analysis checkouts for this recovery:

- `config/day_profiles/slurm/templates/rule_config.yaml`: raised `rtg_vcfeval.mem_mb` to `650000`, `rtg_vcfeval.parse_mem_mb` to `128000`, and routed RTG ROI/parse work to `i384nvme,i192hugenvme`; raised alignstats memory in active analysis configs to `250000`.
- `workflow/rules/rtg_vcfeval.smk`: use explicit `config["rtg_vcfeval"]["mem_mb"]` and `config["rtg_vcfeval"]["parse_mem_mb"]` resources, with no memory fallback.
- `workflow/scripts/parse-vcfeval-summary.py`: create sanitized ROI intermediate directories before writing stripped VCFs, and run `bcftools`, `tabix`, and variant-classification commands with fail-hard `subprocess.run(..., check=True)` calls.
- `workflow/rules/alignstats.smk`: active checkouts now expose `mem_mb=config["alignstats"]["mem_mb"]` to Slurm for both Sentieon alignstats rules.
- `workflow/rules/alignstats_compile.smk`: active checkouts now include the `produce_alignstats.done` output wrapper so the target can finish cleanly once heavy alignstats outputs exist.

## Final Output Evidence

| Analysis | Key outputs |
| --- | --- |
| Current model | `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz` (`520192555` bytes); `.tbi` (`1799286` bytes); `other_reports/giab_concordance_mqc.tsv` (`17028` bytes); `other_reports/alignstats_combo_mqc.tsv` (`6593` bytes); `other_reports/alignstats_gs_mqc.tsv` (`6593` bytes); `logs/produce_alignstats.done`. |
| Prior model | `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz` (`623731699` bytes); `.tbi` (`1825615` bytes); `other_reports/giab_concordance_mqc.tsv` (`16926` bytes); `other_reports/alignstats_combo_mqc.tsv` (`6593` bytes); `other_reports/alignstats_gs_mqc.tsv` (`6593` bytes); `logs/produce_alignstats.done`. |
