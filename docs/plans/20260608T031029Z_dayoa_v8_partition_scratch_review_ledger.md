# DAYOA v8 Partition/Scratch Review Ledger

## Scope

Review and update active DayOA Slurm rule scheduling so alignment and deduplication work targets the v8 NVME partitions and uses `/scratch` rather than `/dev/shm` for temp/sort work.

## Safety Boundary

- No DayOA workflow execution in this pass.
- No raw `snakemake` invocation.
- No cluster create/update/delete.
- Existing unrelated dirty edits are preserved.

## Rows

| Row | Owner | Task | Status | Evidence |
| --- | --- | --- | --- | --- |
| G0-001 | Agent 1 | Record branch, dirty files, repo instructions, and prior `/scratch` context. | SUCCESS | Branch `jem-dev`; dirty files present before this pass: `config/day_profiles/slurm/templates/rule_config.yaml`, `tests/test_ont_fastq_contracts.py`, `workflow/rules/common.smk`, `workflow/rules/go_left.smk`. Read `AGENTS.md` and `/Users/jmajor/.codex/AGENTS-HOW-TO-RUN-DAYOA.md`; no workflow or raw `snakemake` commands were run. |
| INV-001 | Agent 2 | Inventory active Slurm rule partitions, memory, and temp directories. | SUCCESS | Found active hard-coded retired partitions in top-level `workflow/rules/*.smk` and `/dev/shm` temp roots in align/dedup rule shells. Deprecated copies under `workflow/rules/to-deprecate/` were intentionally excluded. |
| CFG-001 | Agent 3 | Route alignment and deduplication rules to `i384nvme,i192nvme`/NVME-appropriate v8 partitions. | SUCCESS | `bwa_mem2a_aln_sort`, `sentmm2_align_sort`, `sentmm2ont_align_sort`, `strobe_align_sort`, `doppelmark`, and `sent_dedup` now include `i384nvme,i192nvme`; active rule files no longer hard-code retired `i192mem`, `i192bigmem`, or `bcl2fq-*` partitions. |
| SCRATCH-001 | Agent 4 | Move relevant align/dedup temp dirs from `/dev/shm` to `/scratch`. | SUCCESS | Main align/sort and hybrid align/markdup temp roots now use `/scratch`; `sent_dedup.tmp_base` is `/scratch`. Static scan found no `/dev/shm` in the guarded align/dedup rule set. |
| TEST-001 | Agent 5 | Add/update tests for v8 partitions, required `mem_mb`, and no `/dev/shm` in align/dedup scheduling. | SUCCESS | Added `tests/test_slurm_profile.py` checks for active-rule retired partitions, NVME align/dedup sections, and no `/dev/shm` in guarded align/dedup rule files. Updated the `go_left` test to match the existing conditional `sex_args` behavior. |
| VALID-001 | Agent 6 | Run focused pytest without workflow execution. | SUCCESS | Focused: `python -m pytest tests/test_slurm_profile.py tests/test_slurm_caller_partitions.py tests/test_sentdhiomr_resource_tuning.py tests/test_ont_fastq_contracts.py -q` -> `19 passed`. Full: `python -m pytest -q` -> `284 passed`. |
| REPORT-001 | Agent 7 | Report changed files, tests, blockers, and residual risks. | SUCCESS | Reported in final response. Residual: deprecated rule copies still contain old partitions and `/dev/shm`; left unchanged by scope. |
