# BCL Convert Workflow

DayOA BCL Convert workflows consume mounted Illumina run directories supplied by `daylily-ephemeral-cluster`. The input run directory should be read in place from `config/runs.tsv` `RUN_DIR`; the workflow must not copy the full run folder into the analysis result tree before demultiplexing.

## Targets

| Target | Purpose |
|---|---|
| `produce_bclconvert_fastqs` | Demultiplex a mounted Illumina run directory into FASTQs. |
| `produce_bclconvert_metrics` | Generate demux metric TSVs and MultiQC custom-data inputs. |
| `produce_bclconvert_multiqc` | Build the focused BCL Convert MultiQC report. |
| `produce_bclconvert_fastqs_and_metrics` | Run demux plus metric generation. |
| `produce_illumina_run_qc_and_bclconvert` | Run mounted Illumina run QC and BCL Convert in one run-context workflow. |

## Mounted Input Contract

`config/runs.tsv` must include a valid Illumina row with `PLATFORM=ILMN`, `RUN_DIR`, `SAMPLE_SHEET`, and `OUTPUT_ROOT`. `RUN_DIR` must contain:

```text
Data/Intensities/BaseCalls/L001/
Data/Intensities/BaseCalls/L002/
...
```

The rule discovers every `L###` lane directory and submits one `run_bclconvert_lane` job per lane. Each lane job reads the mounted run directory directly and writes lane-local outputs under:

```text
<output-root>/bclconvert/lane_fastqs/L###/
<output-root>/bclconvert/lane_reports/L###/
```

By default, `bclconvert.merge_lane_fastqs: false`. The local `run_bclconvert` rule only records that lane FASTQs are ready, and downstream DayOA steps consume the lane-level `fastq_list.csv` and report files in place. This avoids an unnecessary serial stitch step because alignment can stream the lane FASTQs directly into BWA.

If a consumer explicitly needs the merged legacy tree, set `bclconvert.merge_lane_fastqs: true`. In that mode `run_bclconvert` moves FASTQs into the standard final FASTQ directory and writes merged reports under `<output-root>/bclconvert/fastqs/Reports/`.

After demultiplexing, `bclconvert_demux_fastq_qc` prepares one FastQC input link for every demultiplexed FASTQ listed by the selected report set. Link names are composed as:

```text
<RUNID>.L<lane>.<sample>.<read-group>.R1.fastq.gz
<RUNID>.L<lane>.<sample>.<read-group>.R2.fastq.gz
```

The helper fails before FastQC when two rows would produce the same MultiQC/FastQC sample identifier or when the same source FASTQ is listed more than once. That is intentional: demux QC must not silently overwrite R1/R2, lane, read-group, or repeated-sample evidence.

## Terminal QC And MultiQC

`produce_bclconvert_fastqs_and_metrics` ends with:

1. lane-split BCL Convert;
2. a local lane-ready marker by default, or an optional legacy lane merge when `merge_lane_fastqs: true`;
3. generated DayOA `generated.units.tsv`;
4. normalized BCL Convert demux metric TSVs;
5. collision-safe demux FastQC input preparation;
6. FastQC over every demultiplexed FASTQ, including undetermined FASTQs when BCL Convert emits them;
7. focused MultiQC report generation.

The focused report includes `bclconvert`, `fastqc`, and `custom_content` modules. The custom tables include demux stats, lane summary, FASTQ manifest, demux FastQC manifest, unknown barcodes, and index hopping when present.

## Default Demux Settings

The Slurm profile targets solo 192-vCPU BCL Convert jobs:

```yaml
bclconvert:
  threads: 192
  mem_mb: 360000
  partition: "i192mem,i192bigmem"
  merge_lane_fastqs: false
  parallel_tiles: 24
  conversion_threads: 4
  compression_threads: 64
  decompression_threads: 32
  fastq_gzip_compression_level: 1
  shared_thread_odirect_output: true
  output_legacy_stats: true
  num_unknown_barcodes_reported: 1000
  demux_qc_threads: 32
  demux_qc_mem_mb: 64000
  barcode_mismatches_index1: 0
  barcode_mismatches_index2: 0
```

The lane sample-sheet helper injects these mismatch settings into each generated lane sample sheet:

```csv
BarcodeMismatchesIndex1,0
BarcodeMismatchesIndex2,0
```

Other BCL Convert sample-sheet settings are implemented in `workflow/scripts/prepare_bclconvert_lane_samplesheet.py` but remain unset by default. Set them only when validating the corresponding demux contract.

## Manual Validation Workset

For a manual zero-mismatch validation run, make the workset name explicit:

```bash
day-clone -t <git_ref> -d bclconvert_0_mm
cd /fsx/analysis_results/ubuntu/bclconvert_0_mm/daylily-omics-analysis
source dyoainit
dy-a slurm hg38_broad
dy-r produce_bclconvert_fastqs_and_metrics -p -j 20 -k --config run_context_file=config/runs.tsv bootstrap_bclconvert=true
```

Before exporting a combined run-QC/BCL workdir, verify that no run-directory symlink remains under `config/run_dir_links/`. DayOA output should contain BCL results and generated reports, not a copied mounted run folder.
