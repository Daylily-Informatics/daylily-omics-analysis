# Daylily `bcl-convert` Bootstrap Prompt for Codex Mac Desktop

Use this prompt in **multi-agent planning mode** while working in the already-checked-out `daylily-omics-analysis` repository.

## What I already verified in the repo

Treat these as grounded facts from the current checkout and preserve them unless you verify otherwise in code:

- `workflow/rules/bcl2fq.smk` exists, but it is **legacy/orphaned** and is **not included** by `workflow/Snakefile`.
- `workflow/rules/bcl2fq.smk` runs **`bcl2fastq`**, not `bcl-convert`.
- `workflow/rules/bcl2fq.smk` only hard-codes **lanes L001-L004** and is therefore not suitable for the uploaded NovaSeq X sample sheet that uses **lanes 1-8**.
- `workflow/rules/bcl2fq.smk` calls `at2mgsamp_sheet.py`, which does **not** exist in this repo.
- `workflow/rules/common.smk` currently loads `config/samples.tsv` and `config/units.tsv` at parse time and **hard-fails if `units.tsv` is empty**.
- `workflow/rules/workflow_staging.smk` currently assumes `RU[0]` and `EX[0]` exist, so blank bootstrap tables break parse-time globals.
- The uploaded `SampleSheet (1).csv` is a **Sample Sheet v2** for **NovaSeqXSeries** using **BCL Convert 4.3.16**, **dual 10 bp indexes**, and **lanes 1-8**.

Do **not** try to salvage the old `bcl2fq.smk` path. Build a new path.

## Architecture to implement

Implement one clean bootstrap subsystem for Illumina demultiplexing with `bcl-convert`.

### Goal

Add a new workflow path that:

1. accepts a valid `config/samples.tsv`
2. accepts a `config/units.tsv` that may be missing or blank
3. accepts a Sample Sheet v2 CSV like the uploaded NovaSeq X example
4. runs **`bcl-convert`** against an Illumina run folder
5. emits demultiplexed **R1/R2 FASTQs per sample and lane**
6. preserves **Undetermined / unindexed** FASTQs
7. writes a **generated units TSV** for the demultiplexed known samples
8. writes **index / demux metrics summaries** using the BCL Convert native report CSVs
9. generates a **MultiQC** report for the demux step

### Non-goals for this V1

Do not try to make downstream analysis targets consume the newly generated units TSV in the same Snakemake invocation. That is the wrong fight because the repo currently loads tables at parse time. V1 is a **bootstrap demux workflow** that produces FASTQs, reports, and a generated units TSV for the next run.

### Runtime model

Use a **host-installed `bcl-convert` binary** provided outside the repo, not conda packaging.

Reason:
- `bcl-convert` is proprietary vendor software
- there is no official conda package path to depend on
- a clinical AWS deployment should pin an Illumina-supported installed version on the cluster image

Expose the executable path as config, defaulting to `bcl-convert` on `PATH`.

## Files to add or change

### Add

- `workflow/rules/bclconvert.smk`
- `workflow/scripts/parse_bclconvert_samplesheet.py`
- `workflow/scripts/bclconvert_fastq_list_to_units.py`
- `workflow/scripts/bclconvert_metrics_summary.py`
- `workflow/envs/bclconvert_metrics_v0.1.yaml`
- `docs/workflows/bclconvert_bootstrap.md`

### Modify

- `workflow/Snakefile`
- `workflow/rules/common.smk`
- `workflow/rules/workflow_staging.smk`
- `config/day_profiles/local/templates/rule_config.yaml`
- `config/day_profiles/slurm/templates/rule_config.yaml`
- optionally `README.md` if there is already a place describing manifest bootstrapping

## Required behavior

### 1. New config block

Add a config block shaped roughly like this in the profile templates. Keep naming consistent with repo style.

```yaml
bclconvert:
  executable: "bcl-convert"
  run_dir: ""
  sample_sheet: "config/SampleSheet.csv"
  output_root: "results/bclconvert"
  run_id: ""
  libprep: "PCR-FREE"
  seq_vendor: "ILMN"
  seq_platform_override: ""
  force: false
  keep_undetermined_fastqs: true
  sampleproject_subdirectories: false
  strict_mode: false
  first_tile_only: false
  extra_args: ""
```

`run_id` behavior:
- if explicitly configured, use it
- else derive from SampleSheet `RunName`
- sanitize whitespace and slashes

### 2. Bootstrap mode in parse-time table loading

Change `workflow/rules/common.smk` so that a **blank or missing `units.tsv` is allowed only for the new bootstrap demux target(s)**.

Do this safely.

Do **not** weaken validation for the rest of the workflow.

Recommended approach:
- detect whether the requested targets include the new bootstrap target(s)
- if yes, allow `units.tsv` to be missing or empty
- in that case, do not construct normal `samples` metadata from units
- instead expose a minimal bootstrap context that is enough for the demux rules to run
- preserve the current strict behavior for all non-bootstrap targets

### 3. Workflow staging must not require `RU[0]` / `EX[0]` in bootstrap mode

Update `workflow/rules/workflow_staging.smk` to avoid dereferencing `RU[0]` and `EX[0]` when bootstrap demux mode is active.

### 4. New demux rules

Implement a new ruleset in `workflow/rules/bclconvert.smk`.

At minimum include:

#### `rule bclconvert_validate_inputs`

Inputs:
- configured Sample Sheet
- configured `samples.tsv`
- configured run directory

Outputs:
- a validation sentinel under `results/bclconvert/<run_id>/logs/`
- a normalized copy of the sample sheet under the same run directory
- a parsed sample sheet TSV or JSON artifact for downstream rules

Checks:
- Sample Sheet exists and has `[BCLConvert_Settings]` and `[BCLConvert_Data]`
- uploaded example is v2 style, so v2 must be supported first-class
- `Sample_ID` values in the sample sheet must be present in `config/samples.tsv`
- lane numbers in the sample sheet must be valid integers
- duplicate `(Lane, Sample_ID, index, index2)` tuples must be rejected
- dual index fields must be preserved as strings

#### `rule run_bclconvert`

Runs the host executable with something equivalent to:

```bash
bcl-convert \
  --bcl-input-directory <run_dir> \
  --output-directory <results/bclconvert/<run_id>/fastq> \
  --sample-sheet <normalized_samplesheet.csv>
```

Add optional flags from config only when explicitly enabled.

Do not guess undocumented flags.

Outputs must include at least:
- `Reports/fastq_list.csv`
- `Reports/Demultiplex_Stats.csv`
- `Reports/Top_Unknown_Barcodes.csv` if produced
- `Reports/Index_Hopping_Counts.csv` if produced
- a completion sentinel

Do not split the execution by lane using the old tile logic. Let `bcl-convert` handle the run correctly.

#### `rule bclconvert_generate_units_tsv`

Read `Reports/fastq_list.csv` and produce a generated units table for **known samples only**.

Output path:
- `results/bclconvert/<run_id>/tables/generated.units.tsv`

One row per **sample-lane** FASTQ pair.

Populate at least these columns:
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

Field rules:
- `RUNID`: configured `run_id`
- `SAMPLEID`: Sample_ID from sample sheet / fastq list
- `EXPERIMENTID`: use the lane-stable RGID from `fastq_list.csv` if present, otherwise `index1+index2`
- `LANEID`: lane from `fastq_list.csv`
- `BARCODEID`: `index1+index2` if recoverable, else RGID
- `LIBPREP`: config default
- `SEQ_VENDOR`: config default `ILMN`
- `SEQ_PLATFORM`: normalized from Sample Sheet `InstrumentPlatform`, or config override

Do not mutate `config/units.tsv` in place in V1.

#### `rule bclconvert_metrics_summary`

Create normalized TSV summaries under:
- `results/bclconvert/<run_id>/metrics/demultiplex_stats.tsv`
- `results/bclconvert/<run_id>/metrics/unknown_barcodes.tsv`
- `results/bclconvert/<run_id>/metrics/index_hopping.tsv`
- `results/bclconvert/<run_id>/metrics/fastq_manifest.tsv`

Use native BCL Convert outputs as source of truth.

Also add a concise rollup TSV or JSON with:
- total PF reads by lane
- reads per sample per lane
- perfect index read counts
- one-mismatch index read counts
- undetermined reads per lane
- top unknown barcode counts by lane
- index hopping counts if the file is populated

#### `rule multiqc_bclconvert`

Generate:
- `results/bclconvert/<run_id>/reports/bclconvert.multiqc.html`

Use the MultiQC BCL Convert module, not the legacy `bcl2fastq` path.

#### `rule produce_bclconvert_fastqs_and_metrics`

Mark this as the user-facing `TARGET`.

It should depend on:
- demux completion
- generated units TSV
- normalized metrics TSVs
- MultiQC report

### 5. Undetermined / unindexed data

Keep Undetermined FASTQs emitted by `bcl-convert`.

Requirements:
- do not discard them
- include them in the metrics summary
- include them in MultiQC inputs
- document where they land on disk

V1 does **not** need to add synthetic `Undetermined` rows into `generated.units.tsv`.
Keep them as explicit files and report rows.

### 6. Statistics tool choice

Use:
- **native BCL Convert report CSVs** as primary source
- **MultiQC** for HTML summary

Do **not** use `nthmost/illuminate` in this implementation.
Do **not** add a dependency on unsupported legacy InterOp parsers.

If you want binary InterOp parsing at all, use Illumina `interop` only in a future change, not in this V1.

## Concrete compatibility targets

The implementation must handle the uploaded example sample sheet characteristics:

- Sample Sheet v2
- `InstrumentPlatform,NovaSeqXSeries`
- `SoftwareVersion,4.3.16`
- `OverrideCycles,Y151;I10;I10;Y151`
- 8 lanes
- 42 distinct sample IDs
- dual 10 bp indexes

## Required tests

Add focused tests for the pure-Python scripts. Do not attempt to integration-test real `bcl-convert` execution in CI.

At minimum test:

1. parsing the uploaded example Sample Sheet into normalized rows
2. rejecting duplicate lane/sample/index tuples
3. generating `generated.units.tsv` from a stub `fastq_list.csv`
4. metrics summarization from stub `Demultiplex_Stats.csv`
5. handling header-only `Index_Hopping_Counts.csv`
6. preserving Undetermined rows in summaries
7. bootstrap mode allowing blank `units.tsv` only for the new target
8. non-bootstrap targets still failing on blank `units.tsv`

## Deliverables format

Work in phases and stop after each phase with concrete results.

### Phase 1
- implement bootstrap parse-time changes
- add Sample Sheet parser script and tests

### Phase 2
- implement `run_bclconvert` wrapper and config plumbing

### Phase 3
- implement generated units TSV and metrics summaries

### Phase 4
- implement MultiQC and docs

For each phase, report:
- exact files changed
- exact behavior added
- any unresolved edge cases
- commands used to test

## Hard constraints

- Do not use `workflow/rules/bcl2fq.smk` as the base implementation
- Do not use `bcl2fastq`
- Do not assume only 4 lanes
- Do not mutate `config/units.tsv` in place
- Do not silently drop Undetermined FASTQs
- Do not broaden this into downstream alignment or variant calling
- Do not invent repo capabilities that are not present

## If you find blockers

If any blocker prevents the exact design above, make the smallest grounded change and explain why. Do not broaden scope.
