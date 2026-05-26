# Altair Validation Package

Altair validation is scoped to the limited PCR-free germline WGS SNV/indel release assay. The validation package separates reportable-range operations from GIAB truth-denominator operations.

## Region Semantics

`Altair_RR_v1` is the controlled reportable range. Release filtering, coverage, callability, and VCF boundary checks use the full controlled RR.

The Benchmark Accuracy Region is sample-specific:

```text
BAR(sample) = Altair_RR_v1 intersect GIAB_HC(sample)
```

Accuracy benchmarking must use the sample BAR only. ClinVar-gene-only, RR-only, GIAB HC-only, whole-genome, global-union, and other non-HC-intersected denominator paths are rejected with `invalid_accuracy_denominator`.

## Chromosome Policy

The default Altair RR chromosome policy is GRCh38 no-alt `chr1` through `chr22` plus `chrX`. The controlled RR manifest must declare expected and observed chromosome sets, plus missing and extra chromosomes. If an approved autosome-only RR is ever used, that policy must be explicit in the controlled manifest; code must not silently infer autosome-only behavior.

When `chrX` is expected but missing from a final BED artifact, the package is `HOLD` unless the controlled manifest supplies an approved autosome-only policy.

## Required Artifacts

`produce_altair_validation_artifacts` writes the following files under `validation_artifacts/` unless `altair_validation.output_dir` is overridden:

| File | Purpose |
| --- | --- |
| `rr_manifest.tsv` | Controlled RR BED metadata: name, path, SHA256, row count, bases, build, chromosome assertion, source, approval record, status, reason. |
| `bar_manifest.tsv` | One row per GIAB sample with RR/GIAB/BAR names, checksums, BAR rows, bases, chromosome set, status, reason. |
| `accuracy_metrics_by_sample.tsv` | SNV and `small_indel_le50` TP/FP/FN, sensitivity, PPV, denominator BED name/SHA, source-row count, status, reason. |
| `accuracy_metrics_pooled.tsv` | Pooled SNV and `small_indel_le50` accuracy metrics across all passing sample rows. |
| `rr_coverage_callability_by_sample.tsv` | Full-RR coverage/callability metrics with RR checksum, depth summaries, 10x/20x fractions, callable definition, and tool/version. |
| `rr_boundary_verification.tsv` | Released VCF boundary and release-scope checks: zero calls outside RR and zero released indels greater than 50 bp are required for PASS. |
| `validation_summary.json` | Overall PASS/HOLD/FAIL plus structured reasons and artifact counts. |

`overall_status` is `PASS` only when required evidence exists and all gates pass. Missing controlled evidence produces `HOLD`. Violated gates, such as invalid denominators or released calls outside RR, produce `FAIL`.

## Profile Inputs

Set these values in the active profile or `--config` before running the target:

```yaml
altair_validation:
  rr_manifest: /path/to/rr_manifest.tsv
  bar_manifest: /path/to/bar_manifest.tsv
  giab_concordance: /path/to/giab_concordance_mqc.tsv
  boundary_verification: /path/to/rr_boundary_verification.tsv
  report_template_docx: /path/to/QUAL-FRM-ALT-001_Altair_Analytical_Variant_Release_QC_Report_Template.docx
  report_docx: /path/to/output.docx
  coverage:
    full_rr_bed: /path/to/Altair_RR_v1.bed
    min_depth: 20
    min_mapq: 20
    callable_definition: "mosdepth DP>=20x over full Altair_RR_v1"
  boundary:
    released_vcfs: []
  output_dir: validation_artifacts
```

If `boundary_verification` is not supplied, the workflow builds it from `boundary.released_vcfs` and `coverage.full_rr_bed`.

## Local Checks

```bash
ruff check .
ruff format --check .
python -m pytest tests/test_altair_validation_contracts.py tests/test_altair_validation_workflow.py tests/test_giab_qc_contracts.py tests/test_multiqc_qc_targets.py -q
```

## Headnode Gate

Remote validation runs must use `daylily-ec`/SSM as `ubuntu` in a login bash shell. After staging the workset manifests and activating the Slurm profile:

```bash
source dyoainit
dy-a slurm hg38
dy-r produce_altair_validation_artifacts -p -j 100 -k -n
dy-r produce_altair_validation_artifacts -p -j 100 -k
```

Copy the resulting `validation_artifacts/` and generated DOCX report into the controlled package path with checksums preserved.
