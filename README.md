# Daylily Omics Analysis

Daylily Omics Analysis is the operator runbook and workflow repository for Daylily whole-genome analysis. It provides the Snakemake workflows, `dy-*` CLI entrypoints, sample/unit table conventions, monitoring helpers, and benchmarking hooks used to run short-read, long-read, and hybrid analyses on a Daylily ephemeral cluster or in smaller local mode.

> **This repo does not create the cluster.** Infrastructure lifecycle lives in [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster). This repo assumes you already have a working headnode/FSx environment or a compatible local install.

> **Production advice:** use tagged releases when you need stability. `main` is active development.

---

## Highlights

### Shortest supported smoke test

Run this on the headnode inside an analysis directory on `/fsx/analysis_results/ubuntu/`.

```bash
tmux new -s dayoa

mkdir -p /fsx/analysis_results/ubuntu/smoke01
cd /fsx/analysis_results/ubuntu/smoke01
git clone git@github.com:Daylily-Informatics/daylily-omics-analysis.git
cd daylily-omics-analysis

. dyoainit
dy-a slurm hg38

cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r produce_snv_concordances -p -k -j 20 -n
dy-r produce_snv_concordances -p -k -j 20
dy-m --interval 10
```

What success looks like:

- results under `results/day/hg38/`
- a fresh Snakemake master log under `.snakemake/log/`
- `daylily.successful_run` on successful real execution

> If your headnode provides `day-clone`, you can use that instead of `git clone`. Plain `git clone` is still fine.

### What the repo gives you

- **Canonical operator CLI**: `dy-a`, `dy-r`, `dy-m`, `dy-g`, `dy-d`
- **Two execution modes**: `local` for debugging, `slurm` for cluster execution
- **Three supported genome builds**: `hg38`, `hg38_broad`, `b37`
- **Packaged smoke-test data** for the bundled 0.01× HG002 examples
- **Benchmark/cost hooks** on successful non-dry-run executions
- **A lot of workflow surface area** without hiding the operator entrypoints behind wrapper magic

---

## Architecture at a Glance

1. **`daylily-ephemeral-cluster` creates and operates compute.**
   It provisions the ParallelCluster headnode, FSx mount, PCUI, budgets, and surrounding AWS scaffolding.

2. **This repo provides workflow execution and operator ergonomics.**
   `dyoainit` exposes the Daylily CLI aliases, validates project/budget context, and ensures the Daylily environment is ready.

3. **Profiles map the same targets to different execution backends.**
   `dy-a local <build>` runs locally. `dy-a slurm <build>` routes work through Slurm.

4. **Reference data is shared and build-scoped.**
   References and annotations are expected under `/fsx/data/genomic_data/...`, while outputs are written into the analysis clone.

5. **Logs are split by responsibility.**
   Snakemake master logs, per-rule Slurm logs, and command history each live in different places. Read them in that order when debugging.

---

## Reference Data / Shared State / Inputs

| Item | Location | Notes |
| --- | --- | --- |
| Sample table | `config/samples.tsv` | Current workflow input format |
| Unit table | `config/units.tsv` | Required partner to `samples.tsv` |
| Built-in smoke-test tables | `.test_data/data/0.01xwgs_HG002_*.tsv` | Bundled minimal examples |
| Override inputs | `--config samples_table=/path units_table=/path` | Use for custom manifests |
| Results | `results/day/<build>/` | Primary outputs by genome build |
| Snakemake master log | `.snakemake/log/<timestamp>` | Read this first when a run misbehaves |
| Slurm task logs | `logs/slurm/<taskname>/*.out` and `*.err` | Per-job stdout/stderr |
| Command history | `day_cmd.log` | Written by `dy-r` / `bin/day_run` |
| Success/failure markers | `daylily.successful_run`, `daylily.failed_run` | Useful for polling/automation |
| References | `/fsx/data/genomic_data/organism_references/H_sapiens/<build>` | Shared cluster data |
| Annotations | `/fsx/data/genomic_data/organism_annotations/H_sapiens/<build>` | Shared cluster data |

> The cluster is ephemeral. The bucket is durable. That is the point.

---

## Cost Monitoring & Budget Enforcement

This repository does not launch AWS infrastructure directly, but it can fan out a lot of work very quickly once you point it at Slurm.

- `dyoainit` validates project/budget context by default
- the biggest cost lever you control from this repo is **how aggressively you submit work**
- dry-runs are cheap; bad Slurm fan-out is not

Practical starting guidance:

- **Local mode**: keep `-j` at `1` or `2`
- **Slurm smoke tests / first real runs**: start around `-j 10` to `20`
- **Large cluster runs**: go wider only after you understand quotas, queue behavior, and spot availability

Main cost drivers:

1. headnode uptime
2. spot fleet size driven by workflow mix and `-j`
3. FSx retention and size
4. retained EBS/other cluster resources after deletion

---

## Installation -- Quickest Start

### Headnode quickstart

Use a fresh shell or `tmux` session in the analysis directory.

```bash
mkdir -p /fsx/analysis_results/ubuntu/smoke01
cd /fsx/analysis_results/ubuntu/smoke01
git clone git@github.com:Daylily-Informatics/daylily-omics-analysis.git
cd daylily-omics-analysis

. dyoainit
dy-a slurm hg38

cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r produce_snv_concordances -p -k -j 20 -n
dy-r produce_snv_concordances -p -k -j 20
dy-m --interval 10
```

### Local quickstart

Use this when you want to debug on a single machine instead of scaling through Slurm.

> `local` changes the execution backend, not the broader bootstrap assumptions. `dyoainit` still expects a Daylily-capable environment with the usual AWS/cluster context unless you have equivalent configuration available.

```bash
. dyoainit
dy-a local hg38

cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r produce_alignstats -p -j 1 -n
dy-r produce_alignstats -p -j 1
```

---

## Installation -- Detailed

### Prerequisites

- a working ephemeral cluster from [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster), **or** a local environment with the Daylily dependencies available
- a shell where `conda`, AWS CLI, and cluster tooling are available
- for Sentieon-backed targets, a valid Sentieon install and license path reachable from the active environment
- enough budget/quota headroom for the executor you plan to use

### Budget and project selection

If you need an explicit project/budget name, initialize with:

```bash
. dyoainit --project <budget-name>
```

If you omit `--project`, `dyoainit` first tries to read the cluster project from `/opt/parallelcluster/shared/cluster-config.yaml`, then validates it for the current user. If that validation fails, it can fall back to `daylily-global`. Do not assume a simple region-name default.

### Shell and session expectations

- source `dyoainit`; do not execute it as a subprocess
- prefer `tmux` for real Slurm runs
- for non-interactive SSH commands to the headnode, use a login shell so PATH/conda aliases load correctly:

```bash
ssh -i <pemfile> ubuntu@<headnode-ip> "bash -l -c 'cd /fsx/analysis_results/ubuntu/<workdir>/daylily-omics-analysis && <command>'"
```

> If this is missing, commands fail in annoying ways: `squeue` disappears, conda setup goes missing, and debugging becomes fiction.

### CLI you should actually use

| Command | Purpose |
| --- | --- |
| `dy-a <local|slurm> <build>` | Activate executor and genome build |
| `dy-r <targets...> [snakemake flags]` | Run workflows |
| `dy-m [--interval N] [--workdir PATH] [--block-and-poll]` | Monitor active work |
| `dy-g <hg38|hg38_broad|b37>` | Set genome build directly |
| `dy-d reset` | Reset a shell that got into a weird state |

---

## Create / Validate / Operate

### 1. Create an analysis directory

Prefer a dedicated workdir on FSx.

```bash
mkdir -p /fsx/analysis_results/ubuntu/<analysis-name>
cd /fsx/analysis_results/ubuntu/<analysis-name>
git clone git@github.com:Daylily-Informatics/daylily-omics-analysis.git
cd daylily-omics-analysis
```

### 2. Initialize the Daylily CLI

```bash
. dyoainit
dy-a slurm hg38
dy-r help
```

What this does:

- exposes the `dy-*` aliases
- sets executor/profile context
- sets `DAY_GENOME_BUILD`
- prepares the environment expected by `bin/day_run`

### 3. Stage input tables

The current workflow expects **paired** `samples.tsv` and `units.tsv` tables.

Smoke-test path:

```bash
cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv
```

Custom input options:

- copy one of the templates under `.test_data/data/` and edit it
- point directly at external tables with `--config samples_table=/abs/path units_table=/abs/path`
- generate small ENA-backed examples with `bin/fetch_err_sources.py` (writes timestamped tables under `conf/` by default)

Example helper usage:

```bash
bin/fetch_err_sources.py --parallel 2 ERR3989446
cp conf/err_source_<timestamp>_samples.tsv config/samples.tsv
cp conf/err_source_<timestamp>_units.tsv config/units.tsv
```

> Older `analysis_manifest.csv` language is legacy. Current runs should use paired `samples.tsv` and `units.tsv` files.

### 4. Dry-run before you submit real work

```bash
dy-r produce_snv_concordances -p -k -j 20 -n
```

Dry-runs are not optional ceremony. They are the cheapest way to catch bad inputs, bad target selection, and bad assumptions.

### 5. Run the workflow

```bash
dy-r produce_snv_concordances -p -k -j 20
```

Representative wider run:

```bash
dy-r produce_snv_concordances produce_manta produce_tiddit produce_dysgu produce_kat produce_multiqc_final_wgs -p -k -j 20
```

### 6. Common targets

| Target | What it does | Typical build |
| --- | --- | --- |
| `produce_snv_concordances` | Illumina short-read SNV calling + concordance | `hg38` |
| `produce_alignstats` | Alignment statistics | any |
| `produce_sentdont_vcf` | ONT long-read SNV calling | `hg38` |
| `produce_sentdpb_vcf` | PacBio long-read SNV calling | `hg38` |
| `produce_sentdug_vcf` | Ultima SNV calling | `hg38_broad` |
| `produce_sentdhio_vcf` | Hybrid Illumina + ONT CLI workflow | `hg38` |
| `produce_sentdhuo_vcf` | Hybrid Ultima + ONT CLI workflow | `hg38_broad` |
| `produce_sentdhiom_vcf` | Hybrid Illumina + ONT modular workflow | `hg38` |
| `produce_sentdhuom_vcf` | Hybrid Ultima + ONT modular workflow | `hg38_broad` |

Use `dy-r help` and tab completion for the rest.

### 7. Monitor and debug

Primary monitor:

```bash
dy-m --interval 10
```

Useful variants:

```bash
dy-m --workdir /fsx/analysis_results/ubuntu/<analysis-name>/daylily-omics-analysis
dy-m --block-and-poll --interval 5
squeue -u "$USER"
```

Read logs in this order:

1. `.snakemake/log/<most_recent_timestamp>`
2. `logs/slurm/<taskname>/*.out` and `*.err`
3. `day_cmd.log`

First-run delays to expect:

- cold container/image pulls
- first env creation
- slow first spot acquisition on a cold cluster

### 8. VERY IMPORTANT — export before delete

Before deleting the cluster, export anything you care about from `/fsx/analysis_results/` back to durable storage.

> If you delete the cluster before exporting results, the analysis workdir on FSx is gone. Not “hard to recover.” Gone.

At minimum:

1. confirm the outputs you want under `results/day/<build>/`
2. export `/fsx/analysis_results/...` back to S3 using your normal FSx data-repository flow or the companion cluster runbook
3. only then delete the cluster with your normal cluster-management process

Representative deletion command *after export is complete*:

```bash
pcluster delete-cluster -n <cluster-name> --region <region>
```

---

## Automation Helper

For tmux sessions and lightweight automation, you can initialize, activate, and run in one sourced command:

```bash
source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances" "-p -k -j 20" "-n"
```

Arguments:

- executor: `local` or `slurm`
- genome build: `hg38`, `hg38_broad`, or `b37`
- targets: quoted, space-separated target list
- flags: quoted Snakemake flags
- final optional argument: `"-n"` for dry-run

> This script must be sourced, not executed.

---

## Costs

The expensive mistakes are predictable:

- leaving the cluster running after the workflow is done
- retaining FSx or EBS unintentionally after cluster deletion
- submitting a very wide DAG before validating the target set
- assuming a high `-j` is always faster or cheaper

Operator advice:

- dry-run every new workflow/manifest combination
- start small, then scale
- keep analysis workdirs organized by run name
- export final outputs promptly
- treat stale cloud resources as bugs, not background scenery

Relevant background docs:

- [`docs/costs/ref.md`](docs/costs/ref.md)
- [`docs/benchmarks/`](docs/benchmarks)
- [`docs/ops/cost_tagging.md`](docs/ops/cost_tagging.md)

---

## Monitoring / Troubleshooting / Known Issues

### Main operator views

- `dy-m` for workflow-aware monitoring
- `squeue -u "$USER"` and `sinfo` for raw scheduler state
- PCUI for quick cluster/node sanity checks
- CloudWatch when the problem looks like cluster health rather than workflow logic

### Known issues

1. **`dy-b` / `day-build` is not a canonical operator command right now.**
   Historical help text and completion still mention it, but `dyoainit` does not currently expose it as a normal alias. Do not build your runbook around `dy-b`.

2. **Historical docs still mention `analysis_manifest.csv`.**
   Current workflow entry expects paired `samples.tsv` and `units.tsv` inputs.

---

## Documentation

Start with the docs that still match the current workflow shape.

| Path | Purpose |
| --- | --- |
| [`docs/ops/dycli.md`](docs/ops/dycli.md) | Current CLI command summary |
| [`docs/ops/config.md`](docs/ops/config.md) | Configuration notes |
| [`docs/ops/tests.md`](docs/ops/tests.md) | Workflow testing notes |
| [`docs/README_sentieon_pangenome_shortreads.md`](docs/README_sentieon_pangenome_shortreads.md) | Specialized Sentieon/pangenome workflow notes |
| [`docs/benchmarks/`](docs/benchmarks) | Benchmark and performance context |
| [`docs/whitepaper/README.md`](docs/whitepaper/README.md) | Background and whitepaper material |

---

## Historical Material / Contributing / Why This Exists

- [`ORIG_README.md`](ORIG_README.md): late-2025 snapshot preserved for reference
- [`docs/ops/analysis_manifest.md`](docs/ops/analysis_manifest.md): legacy manifest-era documentation
- [Daylily GIAB analyses repository](https://github.com/Daylily-Informatics/daylily_giab_analyses): longer-running benchmark/result history

Why the project exists, in one sentence: Daylily is trying to make workflow comparisons more reproducible by treating accuracy, runtime, hardware, and cost as one problem instead of four separate excuses.

Operationally useful contributions are welcome: clearer runbooks, better failure-mode docs, tighter smoke tests, and workflow improvements with reproducible commands.

The current [`CONTRIBUTING.md`](CONTRIBUTING.md) is minimal, so include exact commands, executor/build details, and relevant log paths in your PR description.

---

## License

This project is released under the terms of the [MIT License](LICENSE).