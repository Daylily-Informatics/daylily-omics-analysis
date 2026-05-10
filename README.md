# Daylily Omics Analysis

[![Latest release](https://img.shields.io/github/v/release/lsmc-bio/daylily-omics-analysis?label=latest%20release&color=teal&cacheSeconds=300)](https://github.com/lsmc-bio/daylily-omics-analysis/releases) [![Latest tag](https://img.shields.io/github/v/tag/lsmc-bio/daylily-omics-analysis?label=latest%20tag&color=pink&cacheSeconds=300)](https://github.com/lsmc-bio/daylily-omics-analysis/tags)

Daylily Omics Analysis contains the Snakemake workflows, shell entrypoints, profile configuration, and run documentation used for Daylily whole-genome sequencing analysis. It is specifically tuned to run inside infrastructure created by [`daylily-ephemeral-cluster`](https://github.com/lsmc-bio/daylily-ephemeral-cluster), with Daylily omics/reference data mounted on the headnode and compute nodes under `/fsx/data`.

This repository does not create, update, or destroy AWS infrastructure. Cluster lifecycle, FSx mounts, and production sample staging belong to `daylily-ephemeral-cluster` and its `daylily-ec` CLI. Use `daylily-ec` to stage reads and create or deliver the `samples.tsv` and `units.tsv` manifests for production worksets; this repo consumes those manifests from each analysis clone.

## Current Inputs

Current workflows use paired manifest tables:

| File | Purpose |
| --- | --- |
| `config/samples.tsv` | One row per biological sample and truth/control metadata. |
| `config/units.tsv` | One row per sequencing unit, lane, read pair, CRAM/BAM, or downsampled analysis unit. |

The legacy `config/analysis_manifest.csv` path is historical. Keep it only for old-run conversion notes.

`SUBSAMPLE_PCT` in `units.tsv` is supported for inline FASTQ downsampling. Values must be floats in `(0.0, 1.0]`; use `na` or an empty value when no downsampling is intended.

For production analyses, prefer manifests generated or staged by `daylily-ec` from the operator side. Hand-written copies are acceptable for focused debugging only when the paths, genome build, and `/fsx/data` reference resources have been verified.

## Quick Start

For a local smoke test from a fresh checkout, use the existing `DAY-EC` environment. This verifies wiring and small fixtures; routine full workflows are expected to run on a prepared headnode. The fixture copy commands below write `config/samples.tsv` and `config/units.tsv`, so run them in a scratch checkout or preserve existing manifests first:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
source dyoainit
dy-a local hg38

mkdir -p config
cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r produce_alignstats -p -j 1 -n
dy-r produce_alignstats -p -j 1
```

For a Slurm-backed headnode run, connect through `daylily-ec`/SSM, then use a persistent workset clone. Stage production reads and manifests with `daylily-ec` before running workflow targets:

```bash
cd /fsx/analysis_results/ubuntu
day-clone -t <git-ref-or-tag> -d <workset-name>
cd /fsx/analysis_results/ubuntu/<workset-name>/daylily-omics-analysis

source dyoainit
dy-a slurm hg38

dy-r produce_snv_concordances -p -k -j 20 -n
dy-r produce_snv_concordances -p -k -j 20
```

Run `dy-r help` for available targets and use tab completion after `source dyoainit`.

## CLI Entry Points

| Command | Purpose |
| --- | --- |
| `source dyoainit` | Initialize Daylily shell functions, environment checks, and completion. |
| `dy-a <local|slurm> <build>` | Activate an execution profile and genome build. |
| `dy-r <targets...> [flags]` | Compose and run the Snakemake command. |
| `dy-m [--workdir PATH] [--interval N]` | Monitor command history, master log, Slurm jobs, and recent task logs. |
| `dy-g <hg38|hg38_broad|b37>` | Change genome build in the active shell. |
| `dy-d reset` | Reset Daylily shell state. |

Common flags passed through `dy-r`:

| Flag | Meaning |
| --- | --- |
| `-n` | Dry-run. |
| `-p` | Print shell commands. |
| `-k` | Keep independent jobs running after a failure. |
| `-j N` | Limit concurrent Snakemake jobs. |
| `-T N` | Snakemake retry/attempt flag used by existing Daylily run commands. |
| `--rerun-incomplete` | Re-run incomplete outputs. |
| `--keep-incomplete` | Keep incomplete outputs for debugging failed jobs. |
| `--keep-temp` | Daylily convenience flag translated by `bin/day_run` to Snakemake `--notemp`. |

## Common Workflow Targets

| Target | Typical use |
| --- | --- |
| `produce_alignstats` | Alignment statistics and aggregate `alignstats_combo_mqc.tsv`. |
| `produce_snv_concordances` | GIAB/RTG concordance outputs where truth metadata is present. |
| `produce_sentD_vcf` | Illumina Sentieon DNAscope SNV calling. |
| `produce_deep19_vcf` | DeepVariant 1.9 SNV calling. |
| `produce_sentdont_vcf` | ONT Sentieon SNV calling. |
| `produce_sentdpb_vcf` | PacBio Sentieon SNV calling. |
| `produce_sentdug_vcf` | Ultima Genomics SNV calling, usually on `hg38_broad`. |
| `produce_cgt7p_vcf` | Complete Genomics/MGI Sentieon DNAscope path using `sentcg` and `cgt7p`. |
| `produce_sentdhiom_vcf` | Modular Illumina+ONT hybrid Sentieon workflow. |
| `produce_sentdhuom_vcf` | Modular Ultima+ONT hybrid Sentieon workflow. |
| `produce_manta`, `produce_tiddit`, `produce_dysgu` | Structural variant callers. |
| `produce_htd_calls` | Selected HTD/special callers from `--config htd_callers=[...]`. |
| `produce_verifybamid2_panel_comparison` | Runs selected VerifyBamID2 SNP panels from `--config verifybamid2_panels=[...]` and writes a comparison TSV. |
| `produce_multiqc_seq_data` | MultiQC for input sequence-data QC. |
| `produce_multiqc_alignment` | MultiQC for sequence-data plus alignment and contamination QC. |
| `produce_multiqc_variants` | MultiQC for sequence, alignment, and variant/annotation QC. |
| `produce_multiqc_final`, `produce_multiqc_final_wgs` | Final routine MultiQC aggregation. |

## Complete Genomics / MGI WGS

Complete Genomics T7+ and MGI-style WGS uses the dedicated `sentcg -> smd -> cgt7p` path:

```bash
dy-r produce_alignstats produce_cgt7p_vcf produce_snv_concordances \
  -p -j 20 -k -T 1 \
  --retries 0 --rerun-incomplete --keep-incomplete \
  --config aligners=[sentcg] dedupers=[smd] snv_callers=[cgt7p]
```

This path uses Sentieon BWA MEM with `DNAscopeMGIWGS2.1.bundle/bwa.model`, read group platform `DNBSEQ`, Sentieon duplicate marking, and DNAscope with `DNAscopeMGIWGS2.1.bundle/dnascope.model` plus `--pcr_indel_model none`.

See [`docs/workflows/complete_genomics_sentieon.md`](docs/workflows/complete_genomics_sentieon.md) for model paths, output names, downsampling, and monitoring details.

## Results And Logs

| Item | Location |
| --- | --- |
| Results | `results/day/<build>/` |
| Per-sample outputs | `results/day/<build>/<sample>/` |
| Aggregate reports | `results/day/<build>/other_reports/` |
| Benchmark summary | `results/day/<build>/reports/benchmarks_summary.tsv` |
| Snakemake master logs | `.snakemake/log/<timestamp>.snakemake.log` |
| Slurm logs | `logs/slurm/<rule>/*.{out,err}` |
| Command history | `day_cmd.log` |
| Completion markers | `daylily.successful_run`, `daylily.failed_run` |

When debugging, inspect logs in this order: latest `.snakemake/log` by mtime, relevant `logs/slurm` files by mtime, then the stable rule log under `results/day/<build>/<sample>/.../logs/`.

## Documentation Map

| Document | Purpose |
| --- | --- |
| [`daylily-ephemeral-cluster`](https://github.com/lsmc-bio/daylily-ephemeral-cluster) | Cluster lifecycle, headnode access, sample staging, and manifest generation. |
| [`docs/README.md`](docs/README.md) | Documentation index and current/historical doc policy. |
| [`docs/quickest_start.md`](docs/quickest_start.md) | Minimal smoke-test checklist. |
| [`docs/first_ephemeral_cluster_analysis.md`](docs/first_ephemeral_cluster_analysis.md) | First headnode workset run. |
| [`docs/ops/dycli.md`](docs/ops/dycli.md) | CLI command behavior and monitoring. |
| [`docs/ops/config.md`](docs/ops/config.md) | Profiles, config precedence, sample/unit schema notes. |
| [`docs/ops/tests.md`](docs/ops/tests.md) | Local validation commands. |
| [`docs/ops/multiqc_qc_targets.md`](docs/ops/multiqc_qc_targets.md) | Staged MultiQC targets, runtime gating, and routine vs optional QC policy. |
| [`docs/catalog_of_tools.md`](docs/catalog_of_tools.md) | Code-sourced catalog of Daylily tool integrations, evidence, outputs, and tests. |
| [`docs/ops/dir_and_file_scheme.md`](docs/ops/dir_and_file_scheme.md) | Current result layout and naming conventions. |
| [`docs/ops/workflow_catalog.md`](docs/ops/workflow_catalog.md) | Packaged workflow catalog API and current contents. |
| [`docs/workflows/complete_genomics_sentieon.md`](docs/workflows/complete_genomics_sentieon.md) | Complete Genomics/MGI `sentcg/smd/cgt7p` workflow. |
| [`docs/workflows/bclconvert_bootstrap.md`](docs/workflows/bclconvert_bootstrap.md) | Illumina BCL Convert bootstrap path. |
| [`docs/workflows/ensemble_vcf.md`](docs/workflows/ensemble_vcf.md) | Ensemble VCF workflow notes. |
| [`docs/remote_test_execution.md`](docs/remote_test_execution.md) | Remote tmux/Slurm execution pattern. |

Top-level run notes such as `run_cg.md`, `gotimeplan.md`, `hyb_runbook.md`, `hybrun.md`, and `ugdata.md` are historical records for specific executions. Prefer the canonical docs above for new runs.

## Repository Layout

```text
.
├── bin/                         # dy-cli wrappers and utility scripts
├── config/                      # profiles, genome/supporting config, sample/unit inputs
├── daylily_omics_analysis/      # packaged Python helpers, including workflow catalog
├── docs/                        # canonical docs and historical notes
├── resources/                   # staged supporting data
├── tests/                       # shell and Python validation tests
└── workflow/                    # Snakemake rules, envs, scripts, and schemas
```

## Development Checks

For a documentation-only change, run:

```bash
git diff --check
bash tests/test_cli_commands.sh
bash tests/test_bclconvert_bootstrap.sh
python -m pytest tests/test_complete_genomics_sentieon.py tests/test_workflow_catalog.py
```

For broad workflow changes, run the relevant target dry-run through `dy-r` after `source dyoainit` and `dy-a <profile> <build>`.
 
