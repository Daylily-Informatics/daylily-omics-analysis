# Ultima Run QC Workflow

Ultima run QC is a run-level workflow. It starts from Ultima run-folder evidence, not the routine DayOA `samples.tsv` and `units.tsv` WGS analysis surface.

## Local Run-Folder Mode

Expected future command:

```bash
dy-r produce_ultima_run_qc \
  --config 'run_qc={"ultima":{"local_run_dir":"/fsx/run_dir_mounts/602202","run_id":"602202","application":"native_wgs","strict_mode":true}}' \
  -p -j 20 -k
```

The implementation must read only the named metric/source files it needs. It must not rewrite the run folder.

## S3 Metric-Subset Mode

Expected future command:

```bash
dy-r produce_ultima_run_qc \
  --config 'run_qc={"ultima":{"run_uri":"s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN602202/2026/602202-20260512_1805/","profile":"lsmc","region":"us-west-2","run_id":"602202","application":"native_wgs","strict_mode":true}}' \
  -p -j 20 -k
```

The S3 profile and region must be explicit. The profile must not be `default`.

## Expected Output Tree

Outputs write under:

```text
results/day/<build>/run_qc/ultima/<run_id>/
  normalized/
  multiqc/
  reports/
  logs/
  benchmarks/
```

Important files:

```text
normalized/inventory.tsv
normalized/libraryinfo_samples.tsv
normalized/trimmer_summary.json
multiqc/ultima_run_inventory_mqc.tsv
multiqc/ultima_demux_summary_mqc.tsv
multiqc/ultima_trimmer_stats_mqc.tsv
multiqc/ultima_trimmer_failures_mqc.tsv
multiqc/ultima_flowq_summary_mqc.tsv
multiqc/ultima_snvq_summary_mqc.tsv
multiqc/ultima_coverage_summary_mqc.tsv
multiqc/ultima_picard_summary_mqc.tsv
multiqc/ultima_contamination_mqc.tsv
multiqc/ultima_upload_status_mqc.tsv
multiqc/ultima_unmatched_mqc.tsv
reports/ultima_run_qc.html
reports/ultima_run_qc_summary.tsv
```

## Viewing MultiQC

Immediate mode uses MultiQC custom-data TSVs. A focused run-QC report scans the run-specific `multiqc/` directory plus the DayOA external config:

```bash
multiqc results/day/<build>/run_qc/ultima/<run_id>/multiqc \
  --config config/external_tools/multiqc_config.yaml \
  --outdir results/day/<build>/run_qc/ultima/<run_id>/reports
```

## Final WGS MultiQC

Ultima run QC remains outside routine final WGS MultiQC. To include the run-QC tables in a final report, the future workflow must require an explicit enable flag such as:

```bash
dy-r produce_multiqc_all \
  --config 'multiqc_qc={"enable_tools":["ultima_run_qc"]}' \
  -p -j 20 -k
```

Missing enabled Ultima run-QC outputs must fail the DAG.

