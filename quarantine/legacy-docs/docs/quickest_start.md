# Quickest Start

Use this to verify local workflow wiring without launching a Slurm fleet. This is a fixture smoke test, not the production run path. Production work should be staged and launched through `daylily-ephemeral-cluster` / `daylily-ec` on a prepared headnode with Daylily reference data mounted under `/fsx/references`, `/fsx/control_data`, `/fsx/runtime_assets`, and `/fsx/staging`.

## Prerequisites

- Run from the repository root.
- On macOS, activate the local Daylily execution environment first:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
```

- For real samples, use `daylily-ec` to stage data and create or deliver `samples.tsv` and `units.tsv`; do not use the tiny fixture manifests below as a production template.
- The fixture copy commands below write `config/samples.tsv` and `config/units.tsv`; run them in a scratch checkout or preserve existing manifests first.

## Smoke Test

```bash
source dyoainit
dy-a local hg38

mkdir -p config
cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r produce_alignstats -p -j 1 -n
dy-r produce_alignstats -p -j 1
```

Expected completion markers:

- `daylily.successful_run`
- latest `.snakemake/log/*.snakemake.log` exits cleanly
- outputs under `results/day/hg38/`

If the dry-run is enough for the task, stop after the `-n` command.
