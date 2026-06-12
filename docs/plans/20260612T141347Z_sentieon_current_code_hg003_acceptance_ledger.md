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
| A4 | `agent-models` | Move runtime paths to `sentieon-genomics-202503.03`; preserve current/prior pangenome model contracts. | COMPLETE | Active config/runtime paths point to `sentieon-genomics-202503.03`; ILMN pangenome defaults to `1.2`, with explicit `prior_model` `1.0` and `*_model_mode=prior` override support. Live prior-model attempt from `10.0.6` proved the initially configured prior path was a directory, not a file; patch release updates the explicit prior path to the nested model file. |
| A5 | `agent-tests` | Run slim local tests and static checks. | COMPLETE | `python -m pytest ... -q`: 39 passed in 0.60s. `python -m py_compile ...`: passed. Grep guard finds no stale active pins/commands except negative test assertions. |
| A6 | `agent-release` | Commit/tag DayOA and update/tag DYEC pin if required. | IN_PROGRESS | DayOA `10.0.6` and DYEC `10.0.15` were committed, pushed, and annotated-tagged for the current-code upgrade. DayOA patch release for the explicit prior-model file path is in progress after the first prior-model live run failed fast with `is_file=False`. |
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
