# `ugrun` CLI Contract

The standalone open-source package lives in repo `lsmc-bio/ur-qc`, distribution `ur-qc`, and exposes the primary CLI `ugrun`.

All commands require explicit input paths. Missing paths fail hard.

## Common Options

| Option | Meaning |
| --- | --- |
| `--run-id` | Required when it cannot be parsed unambiguously from `LibraryInfo.xml` or the run root. |
| `--application {native_wgs,ppmseq,scrna,visium,scale,adna,methylseq,test,auto}` | Application profile. `auto` is allowed only when `LibraryInfo.xml` or config identifies the application. |
| `--strict-mode / --no-strict-mode` | Strict mode fails on required missing files and duplicate identifiers. |
| `--checksum-mode {none,sha256-small,sha256-all}` | Optional checksum policy. |
| `--out-dir` | Required output directory. |

## Commands

| Command | Inputs | Outputs |
| --- | --- | --- |
| `ugrun inventory` | `--run-dir`, optional `--libraryinfo-xml`, `--expected-manifest` | `inventory.tsv`, `inventory.json`, `missing_files.tsv`, `warnings.log` |
| `ugrun libraryinfo` | `--libraryinfo-xml` | `libraryinfo_samples.tsv`, `libraryinfo_barcodes.tsv`, `libraryinfo_summary.json` |
| `ugrun trimmer` | trimmer stats, failure-code, and histogram CSVs | `trimmer_stats.tsv`, `trimmer_failure_codes.tsv`, `trimmer_histogram.tsv`, `trimmer_summary.json` |
| `ugrun quality` | `_FlowQ.metric`, `_SNVQ.metric` | `flowq_histogram.tsv`, `snvq_histogram.tsv`, `quality_summary.tsv`, `quality_summary.json` |
| `ugrun coverage` | coverage JSON and MapQ bedGraphs | `coverage_histogram.tsv`, `coverage_summary.tsv`, `mapq_bedgraph_summary.tsv`, `coverage_summary.json` |
| `ugrun picard` | `<run folder>.csv` | `picard_summary.tsv`, `picard_metrics_long.tsv`, `picard_summary.json` |
| `ugrun contam` | `.selfSM.contamination_stats.csv`, `.selfSM.selfSM`, `.selfSM.Ancestry` | `contamination.tsv`, `ancestry.tsv`, `sample_swap.tsv`, `contamination_summary.json` |
| `ugrun header` | CRAM/BAM path, optional reference FASTA | `header_readgroups.tsv`, `header_ultima_tags.tsv`, `header_summary.json` |
| `ugrun upload-status` | `UploadCompleted.json` or `UploadFailed.json` | `upload_status.tsv`, `upload_status.json` |
| `ugrun summarize` | normalized command outputs | `ultima_run_qc_summary.tsv`, `ultima_run_qc_summary.json`, `ultima_run_qc.html` |
| `ugrun multiqc-export` | normalized command outputs | `ultima_*_mqc.tsv`, optional `multiqc_config_ultima.yaml` |

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Command succeeded and required files were present. |
| `1` | Required files are missing in strict mode. |
| `2` | Invalid inputs or config. |
| `3` | Parser or schema error. |

## Example

```bash
ugrun inventory \
  --run-dir /data/602202-20260512_1805 \
  --run-id 602202 \
  --application native_wgs \
  --libraryinfo-xml /data/602202-20260512_1805/602202_LibraryInfo.xml \
  --strict-mode \
  --out-dir results/day/hg38_broad/run_qc/ultima/602202

ugrun multiqc-export \
  --normalized-dir results/day/hg38_broad/run_qc/ultima/602202/normalized \
  --out-dir results/day/hg38_broad/run_qc/ultima/602202/multiqc
```

