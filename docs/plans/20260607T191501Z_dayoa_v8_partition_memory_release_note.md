# DayOA v8 Partition/Memory Release Note

UTC start: 20260607T191501Z

## Status

Implementation rows for DayOA v8 partition/memory behavior are complete, but the DayOA `9.0.0` release tag is blocked by the full local pytest suite.

No cluster was created, updated, or deleted. No raw `snakemake` workflow command was run.

## Implemented

- Active Slurm profile partitions now use the DAY-EC v8 queue model: `i128`, `i192`, `i192nvme`, `i384nvme`, and `i192hugenvme`.
- Legacy active partition names `i192mem`, `i192bigmem`, `bcl-convert`, and `bcl2fq-*` were removed from active Slurm rule config.
- Partitioned rule config entries now carry explicit `mem_mb`.
- BCL Convert temp/scratch defaults moved from `/dev/shm` to `/scratch`.
- Slurm profile Singularity args bind `/scratch:/scratch`.
- `bwa_mem2a_aln_sort` gained:
  - `partition_strategy: spot_price_runtime`
  - `allowed_partitions`
  - `spot_price_region`
  - `spot_price_availability_zone`
  - `partition_instance_catalog`
- `bin/day_run` invokes `python -m daylily_omics_analysis.slurm.spot_partition_order` before Slurm Snakemake launch.
- The dynamic BWA helper orders allowed partitions by current read-only EC2 Spot price history and fails hard when required AWS/spec/price data is unavailable.

## Passing Evidence

Focused v8 checks:

```text
python -m pytest tests/test_spot_partition_order.py tests/test_slurm_profile.py tests/test_multiqc_qc_targets.py tests/test_sentdhiomr_resource_tuning.py -q
31 passed
```

Targeted former failures after test-contract updates:

```text
python -m pytest \
  tests/test_bclconvert_multiqc.py::test_bclconvert_custom_data_is_registered_for_multiqc \
  tests/test_fsx_mount_paths.py::test_active_tracked_files_use_current_dyec_mount_contract \
  tests/test_giab_qc_contracts.py::test_gatk_contam_rule_sets_heap_and_dense_interval_mode \
  tests/test_giab_qc_contracts.py::test_site_mix_contam_rule_is_target_genotype_free \
  tests/test_multiqc_sample_identifiers.py::test_manta_converts_cram_to_bam_before_calling \
  tests/test_slurm_caller_partitions.py::test_slurm_hybrid_snv_sv_callers_try_nvme_partition_first -q
6 passed
```

Static check:

- no legacy active partition values found in `config/day_profiles/slurm/templates/rule_config.yaml`
- no missing `mem_mb` found for partitioned Slurm entries

## Release Blockers

Full suite:

```text
python -m pytest -q
3 failed, 278 passed
```

Blocking tests:

- `tests/test_rule_log_benchmark_contracts.py::test_all_imported_rules_define_required_log_and_benchmark_directives`
- `tests/test_rule_log_benchmark_contracts.py::test_shell_rules_define_benchmark`
- `tests/test_ultima_run_qc_contracts.py::test_ultima_run_qc_spec_package_exists_and_preserves_boundaries`

These failures are outside the v8 partition/memory change:

- benchmark-contract tests report 173 missing log/benchmark entries and 116 shell rules without benchmark directives
- Ultima test expects missing historical file `docs/plans/20260526T074804Z_ultima_run_qc_native_multiqc_ledger.md`

## Release Decision

DayOA `9.0.0` was not tagged. DYEC `9.0.0` should not be tagged until DayOA `9.0.0` exists and DYEC pins/defaults are advanced to that released tag.
