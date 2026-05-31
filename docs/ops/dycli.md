# DayOA CLI Notes

DayOA CLI work starts in the `DAY-EC` conda environment:

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
```

Initialize a workset clone, activate a profile, then run targets:

```bash
source dyoainit
dy-a local hg38
dy-r help
dy-r produce_multiqc_all -n -p -j 1
```

Useful commands:

- `dy-r --version` prints the DayOA command wrapper version.
- `day-monitor` inspects workflow state from an active analysis directory.
- `dy-r <target> -n -p -j 1` performs a dry-run with printed commands.

On a headnode, connect only through `daylily-ec`/SSM and use a login bash shell before invoking `source dyoainit`, `dy-a`, `dy-r`, or `day-monitor`.

## BCL Convert Run-Context Pattern

BCL Convert and combined Illumina run-QC/BCL workflows consume `config/runs.tsv` rows prepared by `daylily-ephemeral-cluster`. The `RUN_DIR` value should point at a mounted run directory, for example `/fsx/run_dir_mounts/<run-id>/`, and DayOA reads that directory in place. Do not copy the mounted Illumina run folder into an analysis workdir.

The BCL Convert rules detect lanes under `Data/Intensities/BaseCalls/L###`, submit one lane job per lane, and merge outputs locally. The generated lane sample sheets enforce zero barcode mismatches by default:

```csv
BarcodeMismatchesIndex1,0
BarcodeMismatchesIndex2,0
```

When validating this behavior manually on a headnode, use a workset name that records the policy:

```bash
day-clone -t <git_ref> -d bclconvert_0_mm
cd /fsx/analysis_results/ubuntu/bclconvert_0_mm/daylily-omics-analysis
source dyoainit
dy-a slurm hg38_broad
dy-r produce_bclconvert_fastqs_and_metrics -p -j 20 -k --config run_context_file=config/runs.tsv bootstrap_bclconvert=true
```
