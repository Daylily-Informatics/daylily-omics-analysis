# BCL Convert Bootstrap Workflow

## Summary
- Add a new bootstrap demux path, `produce_bclconvert_fastqs_and_metrics`, that accepts a valid `config/samples.tsv`, allows blank or missing `units.tsv` **only** for the new `bcl-convert` bootstrap targets, and produces FASTQs, native demux reports, a generated units TSV, and a MultiQC HTML report for the **next** workflow invocation.
- Keep legacy `workflow/rules/bcl2fq.smk` untouched and out of scope. No `bcl2fastq` reuse, no downstream alignment/calling coupling, no in-place mutation of `config/units.tsv`.
- Use host-installed `bcl-convert` only. Map only documented flags from Illumina’s CLI docs: `--bcl-input-directory`, `--output-directory`, `--sample-sheet`, `-f/--force`, `--strict-mode`, `--bcl-sampleproject-subdirectories`, and `--first-tile-only` ([Illumina docs](https://support-docs.illumina.com/SW/BCL_Convert/Content/SW/BCLConvert/CommandLineOptions_swBCL.htm)).
- Treat repo-root `SampleSheet.csv` as the operator input for local/manual runs. Because it is currently untracked, Phase 1 also vendors a committed fixture copy or sanitized derivative under `.test_data/data/bclconvert/` for repeatable tests.

## Public Interfaces
- New config block in both profile templates:
  - `bclconvert.executable`, `run_dir`, `sample_sheet`, `output_root`, `run_id`, `libprep`, `seq_vendor`, `seq_platform_override`, `force`, `keep_undetermined_fastqs`, `sampleproject_subdirectories`, `strict_mode`, `first_tile_only`, `extra_args`, `threads`, `partition`.
  - Default `sample_sheet` is `SampleSheet.csv` to match the current operator-provided input.
  - `threads`/`partition` mirror current `bcl2fq` defaults per profile for V1.
- New targets:
  - `produce_bclconvert_fastqs_and_metrics` as the user-facing bootstrap target.
  - `produce_bclconvert_fastqs` as the lighter companion target used by bootstrap gating.
- New scripts and CLI contracts:
  - `parse_bclconvert_samplesheet.py --sample-sheet --samples-tsv --normalized-out --rows-out`
  - `bclconvert_fastq_list_to_units.py --fastq-list --sample-sheet-rows --run-id --libprep --seq-vendor --seq-platform-override --units-out`
  - `bclconvert_metrics_summary.py --report-dir --demux-out --unknown-out --hopping-out --fastq-manifest-out --rollup-json-out`

## Multi-Agent Split
- **Agent A: bootstrap parse-time context**
  - Owns `workflow/rules/common.smk` and `workflow/rules/workflow_staging.smk`.
- **Agent B: sample-sheet parsing + fixtures + shell tests**
  - Owns `workflow/scripts/parse_bclconvert_samplesheet.py`, `.test_data/data/bclconvert/*`, and `tests/test_bclconvert_bootstrap.sh`.
- **Agent C: workflow wiring + config plumbing**
  - Owns `workflow/rules/bclconvert.smk`, `workflow/Snakefile`, and both `config/day_profiles/*/templates/rule_config.yaml`.
- **Agent D: generated tables + metrics + docs**
  - Owns `workflow/scripts/bclconvert_fastq_list_to_units.py`, `workflow/scripts/bclconvert_metrics_summary.py`, `workflow/envs/bclconvert_metrics_v0.1.yaml`, and `docs/workflows/bclconvert_bootstrap.md`.
- **Integrator**
  - Reviews interfaces between agents, reconciles any rule/script argument mismatches, then runs the dry-runs and shell test suite.

## Phase Plan

### Phase 1
- **Files**
  - `workflow/rules/common.smk`
  - `workflow/rules/workflow_staging.smk`
  - `workflow/scripts/parse_bclconvert_samplesheet.py`
  - `.test_data/data/bclconvert/*`
  - `tests/test_bclconvert_bootstrap.sh`
- **Behavior**
  - Add `_requested_targets()`, `BCL_BOOTSTRAP_TARGETS`, and `BCL_BOOTSTRAP_MODE` in `common.smk`.
  - In bootstrap mode only, allow `units.tsv` to be missing, zero-byte, or header-only; keep strict failure for every other target.
  - Build a **synthetic one-row bootstrap sample context** so always-included modules that read `RU[0]`, `EX[0]`, `samples`, `SAMPS`, and `SSAMPS` still import cleanly. Use:
    - `RUNID = <derived_or_configured_run_id>`
    - `EX = "bclconvert"`
    - `SQ = "bclconvert"`
    - `LANE = 0`
    - `analysis_unit_uid = <run_id>-bootstrap`
    - `r1_path = r2_path = "na"`
  - Keep `get_samp_ids()` strict except for the new bootstrap targets.
  - Make `workflow_staging` use `<run_id>_bclconvert` for `cluster_sample` in bootstrap mode.
  - Implement a Sample Sheet v2 parser that:
    - requires `[Header]`, `[Reads]`, `[BCLConvert_Settings]`, `[BCLConvert_Data]`
    - preserves `Index`/`Index2` as strings
    - validates integer lanes
    - rejects duplicate `(Lane, Sample_ID, Index, Index2)` tuples
    - checks every `Sample_ID` exists in `samples.tsv`
    - writes a normalized CSV plus `samplesheet_rows.tsv`
  - Parsed TSV columns are fixed: `RUN_NAME`, `INSTRUMENT_PLATFORM`, `SOFTWARE_VERSION`, `OVERRIDE_CYCLES`, `LANE`, `SAMPLE_ID`, `INDEX`, `INDEX2`, `SAMPLE_PROJECT`, `SAMPLE_NAME`, `SOURCE_ROW`.
- **Edge cases**
  - `sampleproject_subdirectories=true` with no `Sample_Project` column fails validation.
  - `keep_undetermined_fastqs=false` fails validation in V1; no undocumented suppression flag is used.
- **Test commands**
  - `bash tests/test_bclconvert_bootstrap.sh`
  - `snakemake -n produce_bclconvert_fastqs_and_metrics`
  - `snakemake -n produce_alignstats` with blank `units.tsv` must still fail

### Phase 2
- **Files**
  - `workflow/rules/bclconvert.smk`
  - `workflow/Snakefile`
  - `config/day_profiles/local/templates/rule_config.yaml`
  - `config/day_profiles/slurm/templates/rule_config.yaml`
- **Behavior**
  - Add `include: "rules/bclconvert.smk"` to `workflow/Snakefile`.
  - Add the new `bclconvert` config block to both profile templates.
  - Implement `bclconvert_validate_inputs` and `run_bclconvert`.
  - `run_id` precedence is fixed:
    1. `bclconvert.run_id` if nonempty
    2. `RunName` from the parsed sample sheet
    3. sanitized sample-sheet basename
  - `run_bclconvert` uses only the documented flags above; `extra_args` is appended verbatim last.
  - `run_bclconvert` requires `Reports/fastq_list.csv` and `Reports/Demultiplex_Stats.csv`; optional report files are probed later by the metrics step.
  - Output tree is fixed at `results/bclconvert/<run_id>/...`.
- **Edge cases**
  - No lane splitting override is added; V1 preserves per-lane FASTQs because the input sample sheet includes `Lane`.
  - `first_tile_only` is opt-in only.
- **Test commands**
  - `snakemake -n produce_bclconvert_fastqs_and_metrics`
  - `bash -n workflow/rules/bclconvert.smk` is not applicable; rely on Snakemake dry-run parse

### Phase 3
- **Files**
  - `workflow/scripts/bclconvert_fastq_list_to_units.py`
  - `workflow/scripts/bclconvert_metrics_summary.py`
  - `workflow/envs/bclconvert_metrics_v0.1.yaml`
  - `workflow/rules/bclconvert.smk`
- **Behavior**
  - Implement `bclconvert_generate_units_tsv`:
    - one row per **sample-lane** FASTQ pair
    - exact output columns: `RUNID`, `SAMPLEID`, `EXPERIMENTID`, `LANEID`, `BARCODEID`, `LIBPREP`, `SEQ_VENDOR`, `SEQ_PLATFORM`, `ILMN_R1_PATH`, `ILMN_R2_PATH`
    - filter out `Undetermined`
    - join `fastq_list.csv` back to `samplesheet_rows.tsv` on `(LANE, SAMPLE_ID)` to recover index data if `fastq_list.csv` lacks a usable RGID
    - `EXPERIMENTID = RGID if present else INDEX+INDEX2`
    - `BARCODEID = INDEX+INDEX2 if recoverable else RGID`
  - Implement `bclconvert_metrics_summary`:
    - normalize native report CSVs to TSVs with lowercase snake_case headers and a leading `run_id`
    - preserve all native source columns instead of inventing a new report schema
    - create zero-row TSVs for missing optional reports (`Top_Unknown_Barcodes.csv`, `Index_Hopping_Counts.csv`)
    - treat header-only `Index_Hopping_Counts.csv` as valid and emit an empty normalized TSV
    - preserve `Undetermined` rows in `demultiplex_stats.tsv`, `unknown_barcodes.tsv`, `fastq_manifest.tsv`, and `rollup.json`
  - `rollup.json` must contain:
    - total PF reads by lane
    - reads per sample per lane
    - perfect-index reads
    - one-mismatch-index reads
    - undetermined reads by lane
    - top unknown barcodes by lane
    - index hopping counts if available
- **Test commands**
  - `bash tests/test_bclconvert_bootstrap.sh`
  - The shell test suite must cover all 8 required cases from the prompt

### Phase 4
- **Files**
  - `workflow/rules/bclconvert.smk`
  - `docs/workflows/bclconvert_bootstrap.md`
  - optionally `README.md` if a bootstrap-workflow index section already exists
- **Behavior**
  - Implement `multiqc_bclconvert` inside `workflow/rules/bclconvert.smk` so write ownership stays concentrated.
  - Use existing `config["multiqc"]["config_yaml"]` plus a new `multiqc.bclconvert.env_yaml` entry in the profile templates; do **not** add a new external MultiQC YAML unless the shared config proves insufficient.
  - Generate `results/bclconvert/<run_id>/reports/bclconvert.multiqc.html` from the BCL Convert output directory and native report CSVs.
  - Final target `produce_bclconvert_fastqs_and_metrics` depends on:
    - demux sentinel
    - generated units TSV
    - normalized metrics TSVs
    - `rollup.json`
    - MultiQC HTML
  - Docs explain:
    - required operator inputs (`SampleSheet.csv`, `config/samples.tsv`, `bclconvert.run_dir`)
    - that `units.tsv` may be blank/missing only for the new bootstrap target
    - where `Undetermined` FASTQs land
    - that the generated units TSV is consumed on the **next** workflow run
- **Test commands**
  - `bash tests/test_bclconvert_bootstrap.sh`
  - `snakemake -n produce_bclconvert_fastqs_and_metrics`

## Test Plan
- Keep the repo’s shell-first test style.
- Add a single new shell suite, `tests/test_bclconvert_bootstrap.sh`, with fixture directories under `.test_data/data/bclconvert/`.
- Required assertions:
  1. parser accepts the real NovaSeq X v2 sample sheet
  2. duplicate `(Lane, Sample_ID, Index, Index2)` is rejected
  3. generated units TSV is correct from stub `fastq_list.csv`
  4. metrics summary is correct from stub `Demultiplex_Stats.csv`
  5. header-only `Index_Hopping_Counts.csv` is handled
  6. `Undetermined` rows persist in summaries
  7. bootstrap target allows blank/missing `units.tsv`
  8. non-bootstrap targets still fail on blank/missing `units.tsv`

## Assumptions and Defaults
- `bcl-convert` bootstrap is the **only** path that bypasses the `units.tsv` hard-fail.
- Legacy `bcl2fq` remains orphaned and unchanged in V1.
- `SampleSheet.csv` at repo root is the operator input for manual runs; tests use a committed fixture copy/sanitized derivative so the suite does not depend on an untracked local file.
- No real `bcl-convert` execution is tested in CI; validation is via parser/unit shell tests plus Snakemake dry-runs.
