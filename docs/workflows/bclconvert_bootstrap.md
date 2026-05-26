# BCL Convert Bootstrap Workflow

This workflow is the bootstrap demultiplexing path for Illumina `bcl-convert`.

## Inputs

- `SampleSheet.csv` at the repository root
- `config/samples.tsv`
- `config/units.tsv`
- `bclconvert.run_dir`

For the bootstrap target, `config/units.tsv` may be blank or missing. For every other target, the normal units-table validation still applies.

## Outputs

The workflow writes its results under `results/bclconvert/<run_id>/`:

- `fastq/` for demultiplexed FASTQs
- `fastq/Reports/fastq_list.csv`
- `fastq/Reports/Demultiplex_Stats.csv`
- `tables/generated.units.tsv`
- `metrics/demultiplex_stats.tsv`
- `metrics/unknown_barcodes.tsv`
- `metrics/index_hopping.tsv`
- `metrics/fastq_manifest.tsv`
- `metrics/rollup.json`
- `reports/bclconvert.multiqc.html`
- `results/day/<genome_build>/other_reports/bclconvert_*_mqc.tsv`

`Undetermined` FASTQs stay on disk in the demultiplex output tree and are preserved in the metrics summaries. They are not added to `generated.units.tsv`.

## BCL Metrics For MultiQC

BCL Convert metrics are exported twice:

- Native BCL Convert CSVs stay under `results/bclconvert/<run_id>/fastq/Reports/`.
- Daylily custom-data TSVs are written under `results/day/<genome_build>/other_reports/` so the normal staged/final MultiQC reports can discover them.

The genome-build `other_reports` files are:

| File | MultiQC section | Contents |
| --- | --- | --- |
| `bclconvert_demux_mqc.tsv` | BCL Convert Demultiplex Stats | Per run, lane, sample, and read demultiplex statistics. |
| `bclconvert_lane_summary_mqc.tsv` | BCL Convert Lane Summary | Lane-level total PF reads, perfect/one-mismatch index reads, undetermined reads, and optional report row counts. |
| `bclconvert_fastq_manifest_mqc.tsv` | BCL Convert FASTQ Manifest | BCL Convert `fastq_list.csv` records with produced read paths. |
| `bclconvert_unknown_barcodes_mqc.tsv` | BCL Convert Unknown Barcodes | Top unknown barcode rows when `Top_Unknown_Barcodes.csv` is present. |
| `bclconvert_index_hopping_mqc.tsv` | BCL Convert Index Hopping | Index hopping rows when `Index_Hopping_Counts.csv` is present. |

The first column in each custom-data TSV is `Sample`. For BCL rows, the displayed IDs include the run and lane so multiple lanes or runs do not collide, for example:

```text
<run_id>.L1.<sample_id>.R1
<run_id>.L1
<run_id>.L1.unknown_barcode.<index>.<index2>
```

The rule chain is:

```text
run_bclconvert
  -> bclconvert_metrics_summary
  -> bclconvert_metrics_multiqc_exports
  -> multiqc_bclconvert
```

No symlink is needed in `results/day/<genome_build>/`; the workflow writes the MultiQC-ready files directly into that build-specific `other_reports` directory.

## Targets

| Target | Purpose |
| --- | --- |
| `produce_bclconvert_fastqs` | Run BCL Convert and stop after demultiplexed FASTQs are complete. |
| `produce_bclconvert_metrics` | Gather normalized BCL Convert metrics and write genome-build MultiQC custom-data TSVs. |
| `produce_bclconvert_multiqc` | Gather BCL metrics and build the focused BCL Convert MultiQC HTML. |
| `produce_bclconvert_fastqs_and_metrics` | Full bootstrap path: FASTQs, generated `units.tsv`, normalized metrics, genome-build MultiQC TSVs, and focused BCL Convert MultiQC HTML. |
| `produce_illumina_run_qc_and_bclconvert` | Mounted run-analysis path that runs Illumina InterOp run QC and the full BCL Convert bootstrap demux/report chain in one output tree. |

## Performance Profile

The Slurm profile runs `run_bclconvert` as a 192-vCPU job and maps those CPUs to native BCL Convert sharding knobs:

- `--bcl-num-parallel-tiles 16`
- `--bcl-num-conversion-threads 64`
- `--bcl-num-compression-threads 96`
- `--bcl-num-decompression-threads 16`
- `--fastq-gzip-compression-level 1`

The Slurm profile uses `bclconvert.staging_mode: "output_dev_shm"` by default. This keeps the mounted run directory as the read source, writes BCL Convert output and `TMPDIR` to node-local `/dev/shm`, then copies completed outputs back to the result tree. This avoids trying to copy DRA-mounted run directories whose sparse or apparent size can be much larger than their block usage. The stricter `dev_shm` mode is still available when a run directory is genuinely small enough to copy into memory. Both scratch modes check `/dev/shm` capacity and fail hard if the requested scratch mode cannot fit; neither mode silently falls back to direct FSx output. Scratch is removed at rule exit unless `bclconvert.retain_scratch: true` is set explicitly for debugging.

## Example Commands

Run the full BCL Convert bootstrap path:

```bash
dy-r produce_bclconvert_fastqs_and_metrics -p -j 20 -k
```

Regenerate only the BCL metrics and MultiQC custom-data exports after BCL Convert outputs already exist:

```bash
dy-r produce_bclconvert_metrics -p -j 4 -k
```

Require BCL Convert metrics in the canonical final MultiQC DAG:

```bash
dy-r produce_multiqc_all \
  --config 'multiqc_qc={"enable_tools":["bclconvert"]}' \
  -p -j 20 -k
```

When `bclconvert` is enabled this way, final MultiQC depends on `results/day/<genome_build>/other_reports/bclconvert_metrics_mqc.done`, so Snakemake will not build the final report before the BCL custom-data TSVs exist.

## Generated Units Table

`generated.units.tsv` is meant for the next workflow invocation. It is a known-sample-only units file with one row per sample and lane, using:

- `RUNID`
- `SAMPLEID`
- `EXPERIMENTID`
- `LANEID`
- `BARCODEID`
- `LIBPREP`
- `SEQ_VENDOR`
- `SEQ_PLATFORM`
- `ILMN_R1_PATH`
- `ILMN_R2_PATH`

## Notes

- The workflow uses the BCL Convert native CSV reports as the source of truth for the TSV summaries.
- `produce_bclconvert_metrics` can be run when the BCL Convert outputs already exist and only the genome-build MultiQC custom-data TSVs are needed.
- To make staged/final Daylily MultiQC reports require and include BCL Convert sections in the same run, pass `--config 'multiqc_qc={"enable_tools":["bclconvert"]}'`.
- Missing optional reports are handled by writing empty TSVs.
- `Index_Hopping_Counts.csv` may legitimately contain only a header row; the summary step treats that as an empty report.
