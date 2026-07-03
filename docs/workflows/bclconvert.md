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

By default, `bclconvert.merge_lane_fastqs: false` and `bclconvert.merge_tile_fastqs: false`. The local `run_bclconvert` rule only records that lane FASTQs are ready, and downstream DayOA steps consume the lane-level `fastq_list.csv` and report files in place. This avoids unnecessary serial stitch steps because alignment can stream comma-separated FASTQ lists directly into BWA.

If a consumer explicitly needs the merged legacy tree, set `bclconvert.merge_lane_fastqs: true`. In that mode `run_bclconvert` moves FASTQs into the standard final FASTQ directory and writes merged reports under `<output-root>/bclconvert/fastqs/Reports/`.

## Tile Sharding

The Slurm profile defaults to scheduler-visible tile sharding with `bclconvert.tile_shard_level: "16"`. To restrict the run to selected lanes, set `tile_shard_lanes` to a comma-separated lane list:

```yaml
bclconvert:
  tile_shard_level: "16"
  tile_shard_lanes: "L003"
  tile_shard_threads: 48
  tile_shard_mem_mb: 500000
  tile_parallel_tiles: 8
  tile_conversion_threads: 2
  tile_compression_threads: 24
  tile_decompression_threads: 8
  merge_tile_fastqs: false
```

DayOA discovers exact tile names from `Data/Intensities/BaseCalls/L###/*.filter`, balances them across zero-padded shard names such as `0001_tiles0001-0020`, and passes the exact shard tile set to BCL Convert with `--tiles`. After every shard for a lane finishes, `merge_bclconvert_tile_shards` aggregates lane-level reports and writes a lane-level `fastq_list.csv` that references the unmerged tile-shard FASTQs. Generated units collapse those rows into comma-separated R1/R2 FASTQ path lists per sample/lane. Downstream generated units, demux metrics, FastQC, and MultiQC continue to consume the lane-level reports.

For small diagnostic BCL Convert probes, set `tile_shard_level: "tile_smoke"` with either `tile_shard_tile_limit` or `tile_shard_tile_names`. `tile_smoke` creates exactly one tile-shard job for the selected lane tiles and fails at DAG construction if no explicit tile selection is configured.

Set `bclconvert.merge_tile_fastqs: true` only when a consumer explicitly needs one R1/R2 FASTQ pair per sample/lane. In that mode `merge_bclconvert_tile_shards` concatenates shard FASTQs in shard-name order before writing the lane-level `fastq_list.csv`.

The Slurm profile defaults `bclconvert.shared_thread_odirect_output: true` so BCL Convert uses the shared-thread O_DIRECT output path. Set it to `false` only for a specific experiment or capacity investigation.

After demultiplexing, `bclconvert_demux_fastq_qc` prepares one FastQC input link for every demultiplexed FASTQ listed by the selected report set. Link names are composed as:

```text
<RUNID>.L<lane>.<sample>.<read-group>.R1.fastq.gz
<RUNID>.L<lane>.<sample>.<read-group>.R2.fastq.gz
```

The helper fails before FastQC when two rows would produce the same MultiQC/FastQC sample identifier or when the same source FASTQ is listed more than once. That is intentional: demux QC must not silently overwrite R1/R2, lane, read-group, or repeated-sample evidence.

## Terminal QC And MultiQC

`produce_bclconvert_fastqs_and_metrics` ends with:

1. lane-split BCL Convert;
2. tile-shard report aggregation when `tile_shard_level` is not `lane`, with FASTQ concatenation only when `merge_tile_fastqs: true`;
3. a local lane-ready marker by default, or an optional legacy lane merge when `merge_lane_fastqs: true`;
4. generated DayOA `generated.units.tsv`;
5. normalized BCL Convert demux metric TSVs;
6. collision-safe demux FastQC input preparation;
7. FastQC over every demultiplexed FASTQ, including undetermined FASTQs when BCL Convert emits them;
8. focused MultiQC report generation.

The focused report includes `bclconvert`, `fastqc`, and `custom_content` modules. The custom tables include demux stats, lane summary, FASTQ manifest, demux FastQC manifest, unknown barcodes, and index hopping when present.

## Default Demux Settings

The Slurm profile targets the observed successful `i192hugenvme` BCL Convert profile: 16 tile shards per lane, 48 threads per shard, non-exclusive placement, `/dev/shm` staging, and O_DIRECT output.

```yaml
bclconvert:
  threads: 48
  mem_mb: 500000
  partition: "i192hugenvme"
  exclusive: ""
  tmpdir: "/scratch/dayoa_bclconvert_tmp"
  scratch_output_root: "/scratch/dayoa_bclconvert"
  scratch_available_bytes_min: 100000000000
  merge_lane_fastqs: false
  merge_tile_fastqs: false
  parallel_tiles: 8
  conversion_threads: 2
  compression_threads: 24
  decompression_threads: 8
  tile_shard_level: "16"
  tile_shard_lanes: ""
  tile_shard_threads: 48
  tile_shard_mem_mb: 500000
  tile_parallel_tiles: 8
  tile_conversion_threads: 2
  tile_compression_threads: 24
  tile_decompression_threads: 8
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
day-clone -t <dayoa_version> -d bclconvert_0_mm
cd /fsx/analysis_results/ubuntu/bclconvert_0_mm/daylily-omics-analysis
source dyoainit
dy-a slurm hg38_broad
dy-r produce_bclconvert_fastqs_and_metrics -p -j 20 -k --config run_context_file=config/runs.tsv bootstrap_bclconvert=true
```

Before exporting a combined run-QC/BCL workdir, verify that no run-directory symlink remains under `config/run_dir_links/`. DayOA output should contain BCL results and generated reports, not a copied mounted run folder.
