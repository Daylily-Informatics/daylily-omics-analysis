# Quickest Start

Use this to verify the local workflow wiring without launching a Slurm fleet.

## Prerequisites

- Run from the repository root.
- On macOS, activate the local Daylily execution environment first:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
```

## Smoke Test

```bash
source dyoainit
dy-a local hg38

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
