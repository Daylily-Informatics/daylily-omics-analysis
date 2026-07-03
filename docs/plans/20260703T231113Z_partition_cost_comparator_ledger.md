# Partition Cost Comparator Ledger

Stamp: `20260703T231113Z`

Controlling request: make dynamic Slurm partition ordering choose its comparator from an environment variable (`median`, `mean`, `min`, `max`, `btm-qrtile`), default to median, keep ordering enabled by default for `DAY_PROFILE=slurm`, and add dynamic ordering to compute-intensive active rules that still submit static partition strings.

## Gate 0 Baseline

- Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- Branch: `jem-dev...origin/jem-dev`
- Starting version: `10.0.60`
- Existing behavior: `derive_partition_order()` sorted by `median_usd_per_vcpu_hr`; dynamic ordering was active when `DAY_PROFILE=slurm` unless bypassed by `PARTITION_MAGIC=0` or execution inside an existing Slurm job.
- Boundary: no workflow execution or headnode mutation; source/test change only.

## Rows

| ID | Area | Requirement | Status | Evidence | Terminal Note |
|---|---|---|---|---|---|
| PC-001 | Comparator | Add strict env-var comparator selection with default `median`. | SUCCESS | `daylily_omics_analysis/slurm/spot_partition_order.py` adds `DAYOA_PARTITION_COST_COMPARATOR` with accepted values `median`, `mean`, `min`, `max`, `btm-qrtile`; invalid values raise `SpotPartitionError`. | Comparator selection is strict and defaults to median when unset or blank. |
| PC-002 | Default | Preserve default-on behavior for `DAY_PROFILE=slurm`. | SUCCESS | `derive_partition_order()` still activates when `DAY_PROFILE=slurm`, except explicit bypasses `PARTITION_MAGIC=0` and `SLURM_JOB_ID`; `config/day_profiles/slurm/templates/config.yaml` invokes the helper with `DAY_PROFILE=slurm`. | Slurm profile submissions now call the ordering helper by default before `sbatch`. |
| PC-003 | Rule coverage | Add dynamic partition ordering to active compute-intensive rules still using static partition resources. | SUCCESS | `config/day_profiles/slurm/templates/config.yaml` computes `dy_partition=$(DAY_PROFILE=slurm python -m daylily_omics_analysis.slurm.spot_partition_order "{resources.partition}")` and submits `--partition="$dy_partition"`. | Coverage is implemented at Slurm submission time, so compute-intensive rules and inherited/default `resources.partition` values are ordered without one-by-one static rule wrapping. |
| PC-004 | Tests | Add/update comparator and rule-coverage tests. | SUCCESS | `tests/test_dynamic_resource_helpers.py` adds comparator, default, invalid-comparator, and CLI CSV tests; `tests/test_slurm_profile.py` asserts the Slurm profile orders partitions before `sbatch`. | Tests cover the env-var comparator contract and default-on Slurm profile wrapper. |
| PC-005 | Verification | Run focused DayOA tests and syntax checks. | SUCCESS | `source /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster/activate && python -m pytest tests/test_dynamic_resource_helpers.py tests/test_slurm_profile.py -q` -> `43 passed`; `python -m pytest tests/test_slurm_caller_partitions.py -q` -> `1 passed`; `python -m py_compile daylily_omics_analysis/slurm/spot_partition_order.py` -> passed; `git diff --check` -> passed. | Focused verification passed. Bare `pytest` saw stale ignored bytecode during debugging, so final verification used `python -m pytest` after clearing ignored `__pycache__` files. |
