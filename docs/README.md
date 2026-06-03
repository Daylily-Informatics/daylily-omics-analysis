# DayOA Documentation Index

**Start with the ecosystem boundary.** `daylily-ephemeral-cluster` is the critical cluster, FSx, SSM, reference, staging, export, and downstream registration companion for this repo. Ursa and Bloom are also key Daylily services. DayOA is the execution plane only: it consumes prepared `samples.tsv` and `units.tsv`, runs Snakemake 7 workflows, and emits local evidence.

## Current Documentation

| Area | Document |
|---|---|
| Operator entry point | [`../README.md`](../README.md) |
| Tool and pipeline inventory | [`catalog_of_tools.md`](catalog_of_tools.md) |
| Contribution and pipeline-extension guide | [`contributing.md`](contributing.md) |
| MultiQC operations | [`ops/multiqc_qc_targets.md`](ops/multiqc_qc_targets.md) |
| Results directory structure | [`ops/results_directory_structure.md`](ops/results_directory_structure.md) |
| CLI notes | [`ops/dycli.md`](ops/dycli.md) |
| Example MultiQC reports | [`examples/multiqc/README.md`](examples/multiqc/README.md) |
| BCL Convert run-context workflow | [`workflows/bclconvert.md`](workflows/bclconvert.md) |
| Ultima run QC contracts | [`specs/ultima_run_qc_requirements.md`](specs/ultima_run_qc_requirements.md), [`workflows/ultima_run_qc.md`](workflows/ultima_run_qc.md) |

## Current Runtime Notes

- BCL Convert uses the mounted run directory directly. It does not copy an Illumina run directory into `results/` or `/dev/shm` before demultiplexing.
- BCL Convert launches one lane job per `Data/Intensities/BaseCalls/L###` directory and writes lane-local FASTQs plus reports. Downstream generated units, demux metrics, FastQC, and focused MultiQC consume those lane-level outputs by default.
- Legacy merged FASTQ/report trees are opt-in with `bclconvert.merge_lane_fastqs: true`; enable that only when a downstream consumer explicitly requires the older merged layout.
- BCL Convert terminal targets generate collision-safe FastQC identifiers from run/lane/sample/RG/read fields and include FastQC plus BCL Convert custom data in the focused MultiQC report.
- ONT and Ultima mounted run-QC targets include demux FASTQ QC. ONT uses SeqKit, nanoq, NanoStat, NanoPlot, and focused MultiQC; Ultima uses FastQC, SeqKit, and focused MultiQC.
- Run QC outputs live under `results/runs/<RUNID>/run_qc/<platform>/` unless `config/runs.tsv` provides an explicit `OUTPUT_ROOT`; BCL Convert outputs live under the sibling `results/runs/<RUNID>/bclconvert/` tree.
- The default BCL Convert sample-sheet contract injects `BarcodeMismatchesIndex1,0` and `BarcodeMismatchesIndex2,0` through generated lane sample sheets. Other sample-sheet settings are wired but intentionally unset until explicitly configured.
- Hybrid Ultima+ONT `sentdhuomr` Stage1 now hard-fails on Sentieon driver errors, validates BAMs before Stage2, and handles empty target/refined-region shards explicitly in later stages.
- Sentieon license discovery is explicit. DayOA accepts `SENTIEON_LICENSE` only when it points to a real file, or reads `daylily.sentieon_lic_path` from `~/.config/daylily/daylily_cli_global.yaml`. It does not scan runtime-asset directories for a license.

## Audience And Public Boundary

These docs are meant for operators, workflow developers, platform engineers, and reviewers who need to understand what DayOA owns without reading every rule first. Public pages should explain the repository boundary before internal run history. Internal one-off execution notes belong in `docs/plans/` while active and `docs/jem_working_docs/` after they are terminal historical records.

Do not publish credentials, license file contents, private CloudFront distributions, operator-only bucket prefixes, or run-specific customer/sample identifiers unless they are already public-safe benchmark examples. Use placeholders for environment-specific AWS account, bucket, cluster, and workset values.

Legacy material moved to [`../quarantine/legacy-docs/`](../quarantine/legacy-docs/). The active `docs/plans/` tree remains in place because those files are durable execution ledgers.

## Documentation Flow

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#111827","primaryTextColor":"#ffffff","primaryBorderColor":"#f97316","lineColor":"#38bdf8","secondaryColor":"#0f766e","tertiaryColor":"#581c87","fontFamily":"Inter,Arial,sans-serif"}}}%%
flowchart LR
  Readme["README<br/>operator overview"] --> Ops["ops<br/>runtime contracts"]
  Ops --> Catalog["catalog<br/>tool inventory"]
  Catalog --> Examples["examples<br/>worked reports"]
  Ops --> Plans["docs/plans<br/>execution ledgers"]
```

## Execution Flow

```mermaid
flowchart TD
  Inputs["samples.tsv + units.tsv<br/>explicit workset manifests"]
  Config["config.yaml + profile<br/>explicit references and runtime assets"]
  Init["source dyoainit"]
  Activate["dy-a local/slurm build"]
  Run["dy-r target flags<br/>Snakemake wrapper"]
  Rules["workflow rules"]
  Evidence["logs, benchmarks, _mqc.tsv,<br/>MultiQC data, evidence manifest"]
  Export["DYEC export/registration boundary"]

  Inputs --> Init
  Config --> Activate
  Init --> Activate --> Run --> Rules --> Evidence --> Export
```

## Rules For Future Docs

- Keep top-of-page boundaries explicit: DayOA executes and emits local evidence; external orchestration handles export, registration, import, interpretation, and release.
- Use worked examples with exact commands and exact expected artifacts.
- Mark cluster-dependent examples as requiring a working `daylily-ec`/SSM headnode unless they have been verified live.
- Prefer Mermaid diagrams where they clarify ownership, DAG shape, artifact identity, or replay semantics.
- Do not document fallback behavior. Missing config, missing files, or malformed identity should fail hard.
- Do not grow DayOA into a monolith. New runnable pipelines should be modular DayOA targets when they share DayOA references/evidence contracts, or separate repositories when they are better maintained under Snakemake, Nextflow, WDL, CWL, or another workflow engine.
