# Results Directory Structure

DayOA writes workflow state, logs, and evidence inside the active repository
checkout. On a DAY-EC headnode that checkout normally lives under:

```text
/fsx/analysis_results/<executing_entity>/<analysis_id>/daylily-omics-analysis/
```

The parent analysis directory is the DYEC export source. DayOA paths in manifests,
logs, and evidence records are normally relative to the `daylily-omics-analysis`
checkout inside that export root.

## Analysis Root

```text
/fsx/analysis_results/<executing_entity>/<analysis_id>/
  daylily-omics-analysis/
    config/
    logs/
    benchmarks/
    results/
    .snakemake/
```

| Path | Owner | Purpose |
|---|---|---|
| `config/samples.tsv` | orchestrator input | Sample-manifest workflows use this as the biological sample table. |
| `config/units.tsv` | orchestrator input | Sample-manifest workflows use this as the sequencing-unit table. |
| `config/runs.tsv` | orchestrator input | Run-context workflows use this for mounted run folders, sample sheets, and per-run output roots. |
| `.snakemake/` | Snakemake | Scheduler metadata, DAG state, locks, and timestamped controller logs. |
| `logs/` | DayOA rules | Rule-specific logs when a rule writes to the top-level log tree. |
| `benchmarks/` | DayOA rules | Rule-specific benchmark tables when a rule writes to the top-level benchmark tree. |
| `results/` | DayOA rules | Analysis evidence, reports, run QC, and BCL Convert outputs. |

## Sample-Manifest Results

Sample-manifest workflows write genome-build-scoped evidence under:

```text
results/day/<genome_build>/
```

Common subtrees include:

```text
results/day/<genome_build>/
  <sample_id>/
    align/
      <aligner>/<deduper>/...
  other_reports/
  reports/
```

| Path | Contents |
|---|---|
| `results/day/<genome_build>/<sample_id>/align/...` | Sample-level alignments, alignment QC, variant calls, concordance outputs, and tool-specific outputs. The exact depth is rule and technology dependent. |
| `results/day/<genome_build>/other_reports/` | Cross-sample and custom report inputs, including `*_mqc.tsv` files consumed by MultiQC. |
| `results/day/<genome_build>/reports/DAY_final_multiqc.html` | Final DayOA MultiQC HTML report. This is a report artifact, not the canonical parser contract. |
| `results/day/<genome_build>/reports/DAY_final_multiqc_data/` | Parser-relevant MultiQC data export, including `multiqc_data.json`, `multiqc_general_stats.txt`, `multiqc_sources.txt`, and `multiqc.log`. |
| `results/day/<genome_build>/reports/dayoa_evidence_manifest.json` | Local deterministic evidence manifest with relative paths, sizes, hashes, classifications, and parser-relevance metadata. |

DayOA does not register artifacts, import evidence downstream, or decide release
state. Those actions belong to the external orchestration plane after the DYEC
export has completed.

## Run-Context Results

Run-context workflows read `config/runs.tsv`. Each row has a `RUNID` and may
provide `OUTPUT_ROOT`. If `OUTPUT_ROOT` is blank, DayOA resolves it to:

```text
results/runs/<RUNID>
```

Every run-context output below is relative to that resolved output root.

## Run QC Results

Run QC outputs are created under `run_qc/<platform>` below the resolved run
output root:

```text
results/runs/<RUNID>/run_qc/illumina/
results/runs/<RUNID>/run_qc/ont/
results/runs/<RUNID>/run_qc/ultima/
```

If `config/runs.tsv` sets `OUTPUT_ROOT`, replace `results/runs/<RUNID>` with
that explicit root. For example, `OUTPUT_ROOT=results/runs/run_qc_smoke`
creates:

```text
results/runs/run_qc_smoke/run_qc/illumina/
```

Expected platform subtrees:

| Platform | Output root | Typical contents |
|---|---|---|
| Illumina | `<output-root>/run_qc/illumina/` | `summary.html`, `summary.tsv`, `multiqc_report.html`, `multiqc_inputs/`, `source_run_subset/InterOp/`, `logs/`, `benchmarks/`, and read-fate river files. |
| ONT | `<output-root>/run_qc/ont/` | `tables/`, `pycoqc/`, `nanoplot/`, `demux_fastq_qc/`, `multiqc_report.html`, `ont_demux_fastq.multiqc.html`, `summary.html`, `summary.tsv`, `logs/`, and `benchmarks/`. `produce_ont_run_qc` includes demux FASTQ QC for mounted run contexts. |
| Ultima | `<output-root>/run_qc/ultima/` | `summary.html`, `summary.tsv`, `demux_fastq_qc/`, `ultima_demux_fastq.multiqc.html`, `logs/ultima_run_qc_report.done`, and `benchmarks/`. `produce_ultima_run_qc` includes demux FastQC/SeqKit and focused MultiQC for mounted run contexts with completed demux FASTQs. |

Mounted run directories are inputs. They should remain under orchestrator-owned
paths such as `/fsx/run_dir_mounts/<mount_id>/` and should not be copied into
`results/`.

ONT and Ultima demux FASTQ QC rules scan the mounted `RUN_DIR`, group FASTQs by
the directory that contains them, and derive sample identifiers from the run id
plus the group path relative to `RUN_DIR`. Identifier collisions fail before
MultiQC is run so one group cannot silently overwrite another group's report
section.

## BCL Convert Results

With a run-context row, BCL Convert writes beside `run_qc`, not inside it:

```text
results/runs/<RUNID>/bclconvert/
```

The native lane-split BCL Convert path reads the mounted Illumina run directory
directly and writes:

```text
results/runs/<RUNID>/bclconvert/
  lane_fastqs/L###/
  lane_reports/L###/
  fastqs/              # present only when bclconvert.merge_lane_fastqs=true
    Reports/
  demux_fastq_qc/
    inputs/
    fastqc/
    demux_fastqc_inputs.tsv
  metrics/
  multiqc/
  tables/
  logs/
  benchmarks/
```

`produce_illumina_run_qc_and_bclconvert` therefore creates both:

```text
results/runs/<RUNID>/run_qc/illumina/
results/runs/<RUNID>/bclconvert/
```

By default `bclconvert.merge_lane_fastqs=false`, so generated units, metrics,
demux FastQC, and MultiQC read each lane `fastq_list.csv` directly from
`lane_fastqs/L###/Reports/`. The optional `fastqs/Reports/` legacy merged tree
is created only when `merge_lane_fastqs=true`.

Before exporting a run-context analysis, verify the result tree does not contain
a copied run folder or a live run-directory symlink. The export should include
DayOA outputs, lane FASTQs, demux FastQC outputs, metrics, reports, logs, and
benchmarks. It should not include the read-only DRA-mounted run input.

The demux FastQC input links are named with run, lane, sample, read group, and
read number. DayOA fails before FastQC if those identifiers collide, so MultiQC
does not silently overwrite demux QC sections.

## Quick Inspection Commands

From the DayOA checkout inside an analysis directory:

```bash
find results/day -maxdepth 4 -type d | sort | head -80
find results/runs -maxdepth 5 -type d | sort | head -120
find results -path '*/run_qc/*' -maxdepth 8 -type f | sort | head -80
find results -path '*/bclconvert/*' -maxdepth 8 -type f | sort | head -80
```

From the DYEC export root:

```bash
find daylily-omics-analysis/results -maxdepth 5 -type d | sort | head -120
```
