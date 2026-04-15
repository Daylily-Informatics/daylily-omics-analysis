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

`Undetermined` FASTQs stay on disk in the demultiplex output tree and are preserved in the metrics summaries. They are not added to `generated.units.tsv`.

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
- Missing optional reports are handled by writing empty TSVs.
- `Index_Hopping_Counts.csv` may legitimately contain only a header row; the summary step treats that as an empty report.
