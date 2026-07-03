# DayOA CLI Notes

DayOA CLI work starts in the `DAY-EC` conda environment. On a Mac, activate it before touching this repo:

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
```

Every DayOA command session has three explicit steps. Run them as separate commands so shell functions, aliases, profile variables, and error codes are visible:

```bash
source dyoainit
dy-a local hg38
dy-r help
dy-r produce_multiqc_all -n -p -j 1
```

## Command Model

`source dyoainit` initializes the repository shell state and defines DayOA helper aliases. `dy-a <profile> <build>` activates one configured profile such as `local hg38`, `slurm hg38`, or `slurm hg38_broad`. `dy-r <target> <flags>` is the supported DayOA wrapper for workflow execution; it passes targets and flags through to Snakemake after applying the DayOA profile contract.

Agent/headnode workflow instructions must use `dy-r` instead of calling `snakemake` directly. Direct Snakemake invocations bypass the wrapper contract that operators use for profile, logging, benchmark, and Slurm behavior.

Useful commands and patterns:

| Command | Purpose |
|---|---|
| `dy-r --version` | Print the DayOA command wrapper version. |
| `dy-r help -p -k -j 1 -n` | Validate wrapper help through the active profile without running jobs. |
| `dy-r <target> -n -p -j 1` | Dry-run a target with printed commands. |
| `dy-r produce_alignstats -p -j 20 -k` | Run alignment-stat evidence after manifests and references are present. |
| `dy-r produce_snv_concordances -p -j 20 -k` | Run configured SNV concordance evidence. |
| `dy-r produce_multiqc_all -p -j 20 -k` | Build final MultiQC aggregation after source evidence exists. |
| `day-monitor` | Inspect workflow state from an active analysis directory. |

Missing config, manifests, references, licenses, or runtime assets are errors. DayOA does not infer sample identity, scan for alternate references, or choose replacement runtime assets.

## Headnode Pattern

On a headnode, connect only through `dyec`/SSM and use an interactive login bash shell before invoking `source dyoainit`, `dy-a`, `dy-r`, or `day-monitor`. From the Mac, activate DYEC with `cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster && source ./activate`, then connect with `dyec headnode connect --profile <profile> --region <region> --cluster <cluster>`. New workflow work must start from an explicitly pinned DayOA checkout, using `day-clone -t <dayoa_version> -d <analysis_id>` manually or DYEC `--git-tag <dayoa_version>`. Long workflow work should run inside a persistent, meaningfully named `tmux` session as `ubuntu`.

Before workflow writes, `dyec analysis --help` must work on the headnode. If it does not, refresh the headnode from the activated local DYEC checkout with `dyec headnode configure --profile <profile> --region <region> --cluster <cluster>`.

```bash
exec bash -l
tmux new -s hg003_5x_snv_benchmark
cd /fsx/analysis_results/ubuntu
day-clone -t <dayoa_version> -d <workset>
cd /fsx/analysis_results/ubuntu/<workset>/daylily-omics-analysis
source dyoainit
dy-a slurm hg38
dy-r produce_alignstats produce_snv_concordances -p -j 100 -k
```

Monitoring commands such as `squeue`, `sacct`, `day-monitor`, and log inspection are read-only. Scheduler, node, Slurm service, drain/resume, cancel, requeue, or repair actions require separate operator approval.

## BCL Convert Run-Context Pattern

BCL Convert and combined Illumina run-QC/BCL workflows consume `config/runs.tsv` rows prepared by `daylily-ephemeral-cluster`. The `RUN_DIR` value should point at a mounted run directory, for example `/fsx/run_dir_mounts/<run-id>/`, and DayOA reads that directory in place. Do not copy the mounted Illumina run folder into an analysis workdir.

The BCL Convert rules detect lanes under `Data/Intensities/BaseCalls/L###`, submit one lane job per lane, and merge outputs locally. The generated lane sample sheets enforce zero barcode mismatches by default:

```csv
BarcodeMismatchesIndex1,0
BarcodeMismatchesIndex2,0
```

When validating this behavior manually on a headnode, use a workset name that records the policy:

```bash
day-clone -t <dayoa_version> -d bclconvert_0_mm
cd /fsx/analysis_results/ubuntu/bclconvert_0_mm/daylily-omics-analysis
source dyoainit
dy-a slurm hg38_broad
dy-r produce_bclconvert_fastqs_and_metrics -p -j 20 -k --config run_context_file=config/runs.tsv bootstrap_bclconvert=true
```

Use the most recent released DayOA tag unless the user explicitly asks for another ref. Never rely on the `day-clone` default ref for new analyses.
