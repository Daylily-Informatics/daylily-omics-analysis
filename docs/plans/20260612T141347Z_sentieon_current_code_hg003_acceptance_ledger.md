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
| A6 | `agent-release` | Commit/tag DayOA and update/tag DYEC pin if required. | IN_PROGRESS | DayOA patch train reached `10.0.13`; DYEC pin/self release reached `10.0.22`. A further DayOA patch is being released for 50x-sized Sentieon DNAscope sort/index memory after the ILMN hg38 solo run exposed a 3GB OOM in `sentD_sort_index_chunk_vcf`. |
| A7 | `agent-headnode` | Prepare dyecX4/profile `lsmc` runs from new DayOA tag via persistent `ubuntu` tmux and `dy-r`. | IN_PROGRESS | dyecX4 headnode has DYEC `10.0.22` available locally; Sentieon runtime `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03` verified. Workflow launches use `dyec workflow launch`, whose controller runs `dy-r` in persistent `ubuntu` tmux sessions. |
| A8 | `agent-live-runs` | Dry-run then live-run HG003 acceptance analyses. | IN_PROGRESS | Final acceptance set uses DayOA `10.0.10` for current/prior ILMN pangenome and ONT hg38_broad solo, DayOA `10.0.13` for the latest HiOMR kitchen sink, and a replacement ILMN hg38 solo run from the next DayOA tag after the sort/index memory fix. Current/prior ILMN pangenome and ONT solo are terminal `exit_code=0`; HiOMR kitchen sink is still running as of `2026-06-12T18:03Z`. |
| A9 | `agent-evidence` | DRA export and acceptance-report inputs. | IN_PROGRESS | DRA export receipts are successful for ONT solo, current ILMN pangenome, and prior ILMN pangenome. ILMN hg38 solo and HiOMR kitchen sink exports are pending terminal success. |

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
- `2026-06-12T16:54Z`: DayOA `10.0.11` HiOMR kitchen sink proved the FastQC/samstats memory fix rendered (`fastqc_subsampled` submitted with `62.50G`), then failed in the local `produce_samtools_metrics` gather target. Upstream `gen_samstats` produced the declared stats/flagstat/idxstat files and `.complete` markers; the gather rule declared a touched marker but had no shell/run block.
- `2026-06-12T16:58Z`: patched `workflow/rules/samtools_metrics.smk` so `produce_samtools_metrics` creates its log directory and touches `other_reports/samtools_metrics_gather.done`; added a regression assertion in `tests/test_multiqc_qc_targets.py`.
- `2026-06-12T16:59Z`: focused post-samtools-gather-fix checks passed: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 62 passed; `bash -n bin/dayoa_sentieon_cli` passed; `python -m py_compile workflow/scripts/parse-vcfeval-summary.py` passed; `git diff --check` passed.
- `2026-06-12T17:00Z`: released DayOA `10.0.12` (`1d41e70`) and DYEC `10.0.21` (`15d17c70`) with annotated non-`v` tags pushed to `jem-dev`; local `dyec --json version` reports `10.0.21`.
- `2026-06-12T17:03Z`: DayOA `10.0.12` HiOMR kitchen sink dry-run `sentup_hg003_hiomr_kitchensink_20260612T170300Z_dryrun` completed with `exit_code=0`.
- `2026-06-12T17:05Z`: launched DayOA `10.0.12` HiOMR kitchen sink live run `sentup_hg003_hiomr_kitchensink_20260612T170500Z` with DRA export-on-success to `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/sentup_hg003_hiomr_kitchensink_20260612T170500Z/`.
- `2026-06-12T17:15Z`: ONT solo acceptance run `sentup_hg003_ont5x_hg38b_solo_20260612T162900Z` completed with `exit_code=0`. DRA receipt `/home/ubuntu/daylily-runs/sentup_hg003_ont5x_hg38b_solo_20260612T162900Z/export/fsx_export.yaml` reports `status: success`, `task_lifecycle: SUCCEEDED`, `detached: true`, and `delete_data_in_file_system: false`; destination `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/sentup_hg003_ont5x_hg38b_solo_20260612T162900Z/`.
- `2026-06-12T17:39Z`: ILMN pangenome prior-model acceptance run `sentup_hg003_ilmn30x_pangenome_prior_20260612T162900Z` completed with `exit_code=0`. DRA receipt reports `status: success`, `task_lifecycle: SUCCEEDED`, `detached: true`, and `delete_data_in_file_system: false`; destination `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/sentup_hg003_ilmn30x_pangenome_prior_20260612T162900Z/`.
- `2026-06-12T17:45Z`: ILMN pangenome current-model acceptance run `sentup_hg003_ilmn30x_pangenome_current_20260612T162900Z` completed with `exit_code=0`. DRA receipt reports `status: success`, `task_lifecycle: SUCCEEDED`, `detached: true`, and `delete_data_in_file_system: false`; destination `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/sentup_hg003_ilmn30x_pangenome_current_20260612T162900Z/`.
- `2026-06-12T17:47Z`: DayOA `10.0.12` HiOMR run exposed a mosdepth prefix contract bug: `workflow/rules/mosdepth.smk` used `log.b` as the mosdepth output prefix, causing Snakemake/Slurm to pre-create the prefix path as a zero-byte log file before `mosdepth` could create prefix-derived outputs.
- `2026-06-12T17:48Z`: patched `workflow/rules/mosdepth.smk` to move the mosdepth prefix into `params.prefix`, bind `mem_mb=config["mosdepth"]["mem_mb"]`, remove any stray prefix file before execution, and use `{params.prefix:q}` in the shell. Regression assertions were added to `tests/test_multiqc_qc_targets.py`.
- `2026-06-12T17:49Z`: released DayOA `10.0.13` (`8646c48`) and DYEC `10.0.22` (`e808d990`) with annotated non-`v` tags pushed to `jem-dev`; local `dyec --json version` reports `10.0.22`.
- `2026-06-12T17:49Z`: DayOA `10.0.13` HiOMR kitchen sink dry-run `sentup_hg003_hiomr_kitchensink_20260612T174900Z_dryrun` completed with `exit_code=0`.
- `2026-06-12T17:50Z`: launched DayOA `10.0.13` HiOMR kitchen sink live run `sentup_hg003_hiomr_kitchensink_20260612T175000Z` with DRA export-on-success to `s3://lsmc-ssf-sequencing-data/derived/analysis_results/sentieon-upgrade/ubuntu/sentup_hg003_hiomr_kitchensink_20260612T175000Z/`.
- `2026-06-12T17:55Z`: remaining live analyses are non-terminal: `sentup_hg003_ilmn30x_hg38_solo_20260612T162900Z` is waiting on the final alignstats tail, and `sentup_hg003_hiomr_kitchensink_20260612T175000Z` is actively running HiOMR/QC jobs. No new terminal error has been recorded for the latest HiOMR run.
- `2026-06-12T18:03Z`: ILMN hg38 solo run `sentup_hg003_ilmn30x_hg38_solo_20260612T162900Z` exposed a real OOM in `sentD_sort_index_chunk_vcf`: Slurm job `1425.batch` killed `bedtools sort` while sorting the 1.8G `1-24` Sentieon DNAscope chunk VCF. The rule rendered hardcoded `threads=1`, `vcpu=1`, and `mem_mb=3000` despite the existing `sort_index_sentD_chunk_vcf` config block.
- `2026-06-12T18:06Z`: patched `workflow/rules/sent_DNAscope.smk` so `sentD_sort_index_chunk_vcf` uses the configured env, threads, vCPU, partition, and memory; writes real `.vcf.gz` and `.tbi` outputs instead of touched placeholders; uses `/scratch` temp; and runs `bcftools sort --max-mem`. Slurm `sentD.mem_mb` was raised to `300000` and `sort_index_sentD_chunk_vcf.mem_mb` to `250000` with `sort_mem: 192G`, sized for possible 50x coverage. Regression coverage was added to `tests/test_multiqc_qc_targets.py`.
- `2026-06-12T18:07Z`: focused post-sort-resource-fix checks passed: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 63 passed; `bash -n bin/dayoa_sentieon_cli` passed; `python -m py_compile workflow/scripts/parse-vcfeval-summary.py` passed; `git diff --check` passed.
- `2026-06-12T18:25Z`: forward-only user request recorded: do not stop currently running analyses, but increase future `sentieon_bwa_sort` Slurm memory requests to 350GB. Patch changes `config/day_profiles/slurm/templates/rule_config.yaml` `sentieon.mem_mb` from `300000` to `350000`, while preserving the active runs already launched from DayOA `10.0.14` or earlier. Regression test `test_sentieon_bwa_sort_requests_350gb_on_slurm` proves `workflow/rules/sentieon.smk` rule `sentieon_bwa_sort` binds `mem_mb=config['sentieon']['mem_mb']`.
- `2026-06-12T18:26Z`: focused post-BWA-sort-memory checks passed: `python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py -q` -> 64 passed; `bash -n bin/dayoa_sentieon_cli` passed; `python -m py_compile workflow/scripts/parse-vcfeval-summary.py` passed; `git diff --check` passed.
- `2026-06-12T18:33Z`: follow-on user request recorded: after the new Sentieon acceptance pipelines are passing, rerun the 4NA hybrid validation as eight units through the full SMN12 caller set with `-j 350`. This is gated on terminal passing acceptance evidence; do not stop or restart the currently running acceptance analyses to satisfy the follow-on request.
- `2026-06-12T18:34Z`: read-only dyecX4 poll: `sentup_hg003_ilmn30x_hg38_solo_20260612T181511Z` and `sentup_hg003_hiomr_kitchensink_20260612T175000Z` remain non-terminal with no DRA export receipts yet. Their tmux controllers are still alive; the 4NA `-j 350` rerun is not launched while this acceptance gate is open.
