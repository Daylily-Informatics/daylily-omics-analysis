# Ultima Run QC Requirements

## Purpose

Ultima run QC is execution/data-plane evidence tooling for Ultima Genomics run outputs. It parses vendor files, validates expected sample/barcode evidence, computes run and barcode summaries, emits normalized TSV/JSON/HTML, and exports MultiQC-ready custom-data files.

It must not create clinical release decisions, R2 pass/fail dispositions, release records, or source-vendor evidence rewrites.

## Scope

In scope:

- Local run-folder and S3 metric-subset workflows.
- Native-WGS CRAM-oriented outputs and FASTQ-producing applications when fixtures document the file set.
- Demux-aware sample/barcode completeness from `LibraryInfo.xml`.
- Trimmer, FlowQ, SNVQ, coverage, Picard/basic metrics, contamination/sample swap, unmatched outputs, header metadata, and upload status.
- MultiQC custom data now and future native MultiQC module input later.

Out of scope:

- Full CRAM scanning by default.
- Proprietary binary dependencies for core parsing.
- Silent empty reports when required evidence is missing.
- Routine final WGS MultiQC inclusion unless explicitly enabled.

## Source File Inventory

Observed native-WGS run roots may contain:

| Kind | Examples | Requiredness |
| --- | --- | --- |
| Library/sample metadata | `602202_LibraryInfo.xml` | Required in strict demux-aware mode |
| Sequencing protocol metadata | `602202_SequencingInfo.json` | Required for run identity when present in source inventory |
| Upload status | `UploadCompleted.json`, `UploadFailed.json` | Optional by config, required when `include_upload_status=true` |
| Root trimmer summary | `merged_trimmer-stats.csv`, `merged_trimmer-failure_codes.csv` | Required in native-WGS strict mode when present in expected manifest |
| Per barcode outputs | `<folder>.cram`, `<folder>.cram.crai`, `<folder>.csv`, `<folder>.json` | Required by application profile |
| Quality metrics | `<folder>_FlowQ.metric`, `<folder>_SNVQ.metric` | Required by native-WGS quality profile |
| Trimmer metrics | `<folder>_trimmer-stats.csv`, `<folder>_trimmer-failure_codes.csv`, histogram CSVs | Required for demux/trimming summaries when present |
| Coverage | `<folder>_0.bedGraph.gz`, `<folder>_1.bedGraph.gz`, coverage JSON fields | Optional unless coverage profile is enabled |
| Contamination | `<folder>.selfSM.contamination_stats.csv`, `.selfSM.selfSM`, `.selfSM.Ancestry` | Optional operational QC |
| Unmatched outputs | `<folder>_unmatched.*` | Optional, included when `include_unmatched=true` |
| Header evidence | CRAM/BAM headers | Optional because CRAM reference access can be expensive |

## Metrics Dictionary

| Family | Required normalized outputs | Notes |
| --- | --- | --- |
| Inventory | expected files, observed files, exists, size, mtime, optional checksum | No source mutation. Missing required files fail strict mode. |
| LibraryInfo | run ID, sample ID, barcode ID, barcode sequence, application, unknown XML attributes | Duplicate barcode IDs fail. Duplicate sequences warn or fail by strictness. |
| Demux completeness | expected barcode count, observed barcode count, missing outputs, unmatched outputs | Uses run-scoped sample IDs, not bare biological samples. |
| Trimmer | input reads, matched/demuxed reads, failed reads, failure codes, percentages, histogram bins | Header mapping must be fixture-backed and flexible. |
| FlowQ/SNVQ | totals, histogram bins, p10/p50/p90 where calculable, low/high threshold fractions | Do not equate FlowQ/SNVQ with Illumina Q-score without caveat. |
| Coverage | mean depth, median when recoverable, percent at 1/5/10/20/30/50x, MapQ0/1 bases and intervals | Empty bedGraphs are explicit flags. |
| Picard/basic metrics | wide summary and long key/value rows | Preserve unknown columns. |
| Contamination | FREEMIX, PCT contamination, SNP counts, ancestry, swap indicators | Operational flags only, not clinical disposition. |
| Header | read groups, `SM`, `PL`, `PU`, barcode, flow order, model/pipeline metadata | Optional command, fail clearly if required CRAM/reference is missing. |
| Upload status | completed, completed empty marker, failed, missing, malformed, timestamps, messages | Zero-byte completed markers normalize explicitly. |

## Failure Behavior

- Exit nonzero on invalid input, malformed required files, duplicate required identifiers, and missing required files.
- Strict mode missing required evidence exits `1`.
- Invalid inputs or config exit `2`.
- Parser/schema errors exit `3`.
- Optional files must be marked absent in summaries rather than replaced with synthetic zero rows.
- Unknown fields are preserved in JSON metadata, not discarded.

## Acceptance Criteria

- `produce_ultima_run_qc` remains run-level QC, outside routine final WGS MultiQC.
- All MultiQC custom-data TSVs put `Sample` first.
- Run rows use `Sample=<run_id>`.
- Barcode rows use `Sample=<run_id>.<barcode_id>.<sample_id>`.
- Per-file rows use `Sample=<run_id>.<barcode_id>.<sample_id>.<file_kind>`.
- Unmatched rows use `Sample=<run_id>.unmatched.<file_kind>`.
- Safe tokens strip whitespace, replace slashes with `_`, and allow only `[A-Za-z0-9._+-]`.
- No row emits `Sample` as `R1`, `R2`, `metrics`, or a bare biological sample when run context matters.

