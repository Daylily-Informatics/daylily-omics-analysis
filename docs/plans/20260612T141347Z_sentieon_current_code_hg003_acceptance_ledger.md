# Sentieon Current-Code HG003 Acceptance Ledger

Created: 2026-06-12T14:13:47Z

Cluster: `dyecX4`
AWS profile: `lsmc`
Region: `us-west-2`
DayOA repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
DYEC repo: `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster`
Evidence export root: `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/<analysis-id>/`

## Objective

Bring active DayOA Sentieon-owned runtime code to current upstream versions, tag a clean DayOA release, update DYEC pins as needed, then validate HG003 live analyses from the tagged code:

- Sentieon core `202503.03`
- `sentieon-cli==1.6.3`
- `segdup-caller@v0.6.0`
- current ILMN pangenome model `SentieonIlluminaPangenomeRealignWGS1.2.bundle`
- prior ILMN pangenome model discovered from repo history: `SentieonIlluminaPangenomeRealignWGS1.0.bundle`

## Gate 0 Inventory

| Check | Result |
| --- | --- |
| DayOA branch/status | `## jem-dev...origin/jem-dev`; clean at start |
| DayOA describe | `10.0.5` |
| DYEC branch/status | `## jem-dev...origin/jem-dev`; existing untracked 4NA report artifacts present |
| DYEC describe | `10.0.14` |
| Upstream Sentieon core | Sentieon docs and Bioconda show current `202503.03` |
| Upstream Sentieon CLI | PyPI `sentieon-cli` latest `1.6.3`; released 2026-06-10; requires Python `>=3.11` |
| Upstream Sentieon CLI git tag | `v1.6.3` present |
| Upstream segdup-caller git tag | GitHub tags show `v0.6.0`, released 2026-06-03 |
| Upstream model YAML | Sentieon model YAML updated 2026-06-01; current ILMN pangenome `SentieonIlluminaPangenomeRealignWGS1.2.bundle`, Ultima pangenome `SentieonUltimaPangenomeRealignWGS1.3.bundle` |
| Prior ILMN pangenome model | `SentieonIlluminaPangenomeRealignWGS1.0.bundle`, from DayOA history before current `1.2` pin; on FSx the usable CLI model file is nested at `.../SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle` |

## Agent Ledger

| ID | Agent | Scope | Status | Evidence / Notes |
| --- | --- | --- | --- | --- |
| A0 | `agent-orchestrator` | Own ledger, Gate 0 inventory, final counts, cross-row consistency. | IN_PROGRESS | Gate 0 local repo and upstream-version inventory recorded. |
| A1 | `agent-upstream-versions` | Record current upstream Sentieon core, CLI, segdup-caller, and model bundle versions. | COMPLETE | Sources: Sentieon docs/release notes, Bioconda sentieon recipe, PyPI `sentieon-cli`, GitHub `segdup-caller` tags, Sentieon `sentieon_models.yaml`. |
| A2 | `agent-envs` | Update active Sentieon conda envs to current core/CLI/segdup pins and Python 3.11 where needed. | COMPLETE | Active Sentieon envs now pin `sentieon=202503.03`, `sentieon-cli==1.6.3`, Python `3.11` where CLI is present, and `segdup-caller@v0.6.0`. |
| A3 | `agent-command-shape` | Replace active `sentieon-pangenome` calls with `dnascope-pangenome`. | COMPLETE | Active pangenome rules use `bin/dayoa_sentieon_cli dnascope-pangenome`; stale string remains only as a negative test assertion. |
| A4 | `agent-models` | Move runtime paths to `sentieon-genomics-202503.03`; preserve current/prior pangenome model contracts. | COMPLETE | Active config/runtime paths point to `sentieon-genomics-202503.03`; ILMN pangenome defaults to `1.2`, with explicit `prior_model` `1.0` and `*_model_mode=prior` override support. Live prior-model attempts proved the initially configured prior path was a directory and then that the prior model requires the gnomAD v4.1 population VCF. Patch release selects both prior model file and `prior_pop_vcf` together. |
| A5 | `agent-tests` | Run slim local tests and static checks. | COMPLETE | Current focused suite: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 62 passed. `bash -n bin/dayoa_sentieon_cli`, `python -m py_compile workflow/scripts/parse-vcfeval-summary.py`, and `git diff --check` passed. |
| A6 | `agent-release` | Commit/tag DayOA and update/tag DYEC pin if required. | IN_PROGRESS | DayOA `10.0.6` / DYEC `10.0.15` released for the current-code upgrade; DayOA `10.0.7` / DYEC `10.0.16` released for the explicit prior-model file path. DayOA patch release for the prior-model population VCF contract is in progress after live failure showed `--pop_vcf` ID mismatch. |
| A7 | `agent-headnode` | Prepare dyecX4/profile `lsmc` runs from new DayOA tag via persistent `ubuntu` tmux and `dy-r`. | IN_PROGRESS | dyecX4 headnode has DYEC `10.0.15` installed in `/home/ubuntu/miniconda3/envs/DAY-EC`; Sentieon runtime `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03` verified. |
| A8 | `agent-live-runs` | Dry-run then live-run HG003 acceptance analyses. | IN_PROGRESS | All five HG003 dry-runs passed from DayOA `10.0.6`. Live current pangenome, ILMN hg38 solo, and ONT hg38_broad solo are running; prior pangenome failed before variant calling because the configured `1.0` model path was a directory. |
| A9 | `agent-evidence` | DRA export and acceptance-report inputs. | OPEN | Pending successful live analyses. |

## Required Local Test Command

```bash
python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py -q
```

## Required Headnode Workflow Contract

All DayOA workflow execution on the dyecX4 headnode must use a persistent `ubuntu` tmux login shell with setup as separate commands:

```bash
source dyoainit
dy-a slurm hg38_broad
dy-r ...
```

Raw `snakemake` invocation is out of scope.

## Progress Log

- `2026-06-12T14:50Z`: launched live HG003 ILMN pangenome current model from DayOA `10.0.6`; rendered `bin/dayoa_sentieon_cli dnascope-pangenome`, model `SentieonIlluminaPangenomeRealignWGS1.2.bundle`, `/scratch` temp, and `-t 128`.
- `2026-06-12T14:53Z`: launched live HG003 ILMN pangenome prior model from DayOA `10.0.6`; rendered `dnascope-pangenome`, model `.../SentieonIlluminaPangenomeRealignWGS1.0.bundle`, `/scratch` temp, and `-t 128`.
- `2026-06-12T14:59Z`: prior-model live run failed in `sentieon-cli` argument validation: `argument -m/--model_bundle: The supplied path argument needs the attribute is_file=True, but is_file=False`.
- `2026-06-12T15:07Z`: FSx inspection showed `SentieonIlluminaPangenomeRealignWGS1.0.bundle` is a directory and the actual model file is `SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle`; config/test patch prepared to use that explicit file path.
- `2026-06-12T15:23Z`: DayOA `10.0.7` prior-model live attempt reached `sentieon-cli` and failed with `ERROR:sentieon_cli.pipeline:The ID of the --pop_vcf does not match the model bundle`.
- `2026-06-12T15:31Z`: prior bundle `bundle_info.json` has `SentieonVcfID=population-hprc-v2.0+gnomad-v4.1.0-20251216`; mounted `pop-v20g41-20251216.vcf.gz` header has matching `##SentieonVcfID`. Config/rule patch prepared so `*_model_mode=prior` selects both the nested prior model file and `prior_pop_vcf`.
- `2026-06-12T15:39Z`: live ONT solo run `sentup_hg003_ont5x_hg38b_solo_20260612T143947Z` exited `1`; Sentieon ONT SNV and all SNV concordance ROI outputs completed, but `alignstats` was OOM-killed under rendered `mem_mb=3000`.
- `2026-06-12T15:45Z`: live ILMN hg38 solo run `sentup_hg003_ilmn30x_hg38_solo_20260612T143947Z` exited `1`; both dmd and na `alignstats` jobs were OOM-killed under rendered `mem_mb=3000`, while Sentieon DNAscope continued to produce its chunk VCF.
- `2026-06-12T15:58Z`: root cause traced to `workflow/rules/alignstats.smk` binding threads/vcpu/partition but not `resources.mem_mb`; Slurm profile had an alignstats memory value but the rule did not expose it to Snakemake. Patch binds `mem_mb=config["alignstats"]["mem_mb"]` for BAM and CRAM alignstats rules and raises Slurm alignstats memory to `250000`.
- `2026-06-12T15:59Z`: focused post-fix checks passed: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 62 passed; `bash -n bin/dayoa_sentieon_cli` passed; `python -m py_compile workflow/scripts/parse-vcfeval-summary.py` passed; `git diff --check` passed.
- `2026-06-12T16:17Z`: DayOA `10.0.9` ONT solo rerun rendered the expensive `alignstats` rule with `mem_mb=250000`, `threads=96`, and produced JSON/TSV outputs, then failed in the cheap `produce_alignstats` target wrapper because `workflow/rules/alignstats_compile.smk` declared only input/log/benchmark and no marker output or shell.
- `2026-06-12T16:21Z`: patched `produce_alignstats` to create `results/day/<genome>/logs/produce_alignstats.done` after `other_reports/alignstats_bsummary.tsv` exists; added a regression assertion in `tests/test_multiqc_qc_targets.py`.
- `2026-06-12T16:22Z`: focused post-wrapper-fix checks passed: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 62 passed; `bash -n bin/dayoa_sentieon_cli` passed; `python -m py_compile workflow/scripts/parse-vcfeval-summary.py` passed; `git diff --check` passed.
- `2026-06-12T16:23Z`: all five DayOA `10.0.10` HG003 acceptance dry-runs passed: current pangenome, prior pangenome, ILMN hg38 solo, ONT hg38_broad solo, and HiOMR kitchen sink.
- `2026-06-12T16:26Z`: launched matching DayOA `10.0.10` live analyses with DRA export-on-success to `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/<analysis-id>/`.
- `2026-06-12T16:36Z`: DayOA `10.0.10` HiOMR kitchen sink showed real OOM failures in `fastqc_subsampled` and `gen_samstats`; both rules rendered `mem_mb=3000`. Slurm stderr reported OOM-kill for `fastqc -t 32` and `samtools stats -@ 10`.
- `2026-06-12T16:42Z`: patched `fastqc_subsampled` and `gen_samstats` to bind `mem_mb` from profile config; raised Slurm profile `fastqc.mem_mb` and `gen_samstats.mem_mb` to `64000`; added regression assertions in `tests/test_multiqc_qc_targets.py`.
- `2026-06-12T16:43Z`: focused post-QC-resource-fix checks passed: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 62 passed; `bash -n bin/dayoa_sentieon_cli` passed; `python -m py_compile workflow/scripts/parse-vcfeval-summary.py` passed; `git diff --check` passed.
