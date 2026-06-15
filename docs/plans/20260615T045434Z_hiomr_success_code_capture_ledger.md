# HiOMR Success Code Capture Ledger

Created: 2026-06-15T04:54:34Z

## Objective

Capture the code changes needed to rerun the successful HG003 HiOMR acceptance workflow from a clean DayOA/DYEC release on `jem-dev`.

Successful FSx analysis checkout inspected:

`/fsx/analysis_results/ubuntu/sentup_hg003_hiomr_kitchensink_20260612T185650Z/daylily-omics-analysis`

The successful checkout reported `10.0.16-dirty`.

## Gate 0

| Check | Evidence |
| --- | --- |
| DayOA local branch | `jem-dev` |
| DayOA start point | `10.0.18`, clean tracked worktree before this capture |
| Successful checkout dirty files inspected | `config/day_profiles/slurm/templates/rule_config.yaml`, `tests/test_multiqc_qc_targets.py`, `tests/test_multiqc_sample_identifiers.py`, `workflow/rules/mosdepth.smk`, `workflow/rules/multiqc_final_wgs.smk`, `workflow/rules/rtg_vcfeval.smk`, `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk`, `workflow/rules/vep.smk`, `workflow/scripts/stage_multiqc_inputs.py` |

## Decisions

The dirty checkout contained several fallback/runtime-repair changes. These were not ported because this workspace requires fail-hard behavior unless a fallback is explicitly approved:

- `mosdepth.smk`: did not port zero-coverage sentinel output fabrication.
- `vep.smk`: did not port fallback selection of the first chunk when no non-empty VEP chunks exist.
- `rtg_vcfeval.smk`: did not port `.get(..., default)` memory fallbacks or lower RTG memory settings.

## Ported Changes

| File | Change |
| --- | --- |
| `workflow/rules/rtg_vcfeval.smk` | Set `RTG_MEM` from the explicit Snakemake memory request before `rtg vcfeval`, and create the declared MQC output directory before parser execution. |
| `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk` | Use `INNERPY` for the embedded Python heredoc that resolves the segdup package-data population VCF path. |
| `tests/test_multiqc_sample_identifiers.py` | Assert RTG memory remains explicit, no fallback memory defaults exist, `RTG_MEM` is rendered, and the parse output dir is created. |
| `tests/test_ont_fastq_contracts.py` | Assert the segdup package-data heredoc uses the distinct `INNERPY` delimiter. |

## Validation

Focused checks passed before commit:

```bash
python -m pytest tests/test_sentieon_model_bundle_config.py tests/test_ont_fastq_contracts.py tests/test_snakemake_parser_contracts.py tests/test_complete_genomics_sentieon.py tests/test_htd_callers_contract.py tests/test_multiqc_qc_targets.py tests/test_multiqc_sample_identifiers.py -q
```

Result: `95 passed in 1.29s`.

Additional checks passed:

```bash
python -m py_compile workflow/scripts/parse-vcfeval-summary.py workflow/scripts/stage_multiqc_inputs.py
bash -n bin/dayoa_sentieon_cli
git diff --check
```

## Follow-Up

After the DayOA release is pushed, update DYEC to pin the new DayOA tag and push the DYEC pin release to `jem-dev` so the HG003 HiOMR rerun can launch from clean tagged code.
