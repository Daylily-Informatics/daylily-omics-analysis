# Empty-Unmapped Metagenomics And Runtime Assets Ledger

Controlling plan: chat request, 2026-05-28, "DayOA Empty-Unmapped And Runtime-Asset Release Plan"
Ledger path: `docs/plans/20260528T131713Z_empty_unmapped_metagenomics_runtime_assets_ledger.md`

## Gate 0 Baseline

- DayOA repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- DayOA branch: `codex/dayoa-local-evidence-dewey-refactor-20260528`
- DayOA HEAD: `24c24fcf9e507773e5285fc6431e33d5d4e1e58f`
- DayOA status before this ledger: dirty tracked files in previous stabilization scope:
  `config/day_profiles/local/templates/rule_config.yaml`,
  `config/day_profiles/slurm/templates/rule_config.yaml`,
  `config/external_tools/multiqc_config.yaml`,
  `docs/catalog_of_tools.md`,
  `docs/ops/multiqc_qc_targets.md`,
  `tests/test_contam_identity_bundle.py`,
  `tests/test_htd_callers_contract.py`,
  `tests/test_multiqc_qc_targets.py`,
  `workflow/Snakefile`,
  `workflow/rules/common.smk`,
  `workflow/rules/contam_identity.smk`,
  `workflow/rules/htd_calls.smk`,
  `workflow/rules/multiqc_final_wgs.smk`,
  `workflow/scripts/compile_contam_identity_mqc.py`.
- DYEC repo: `/Users/jmajor/.codex/worktrees/dyec-fsx-dra-mounts/daylily-ephemeral-cluster`
- DYEC branch: `codex/dyec-dewey-registration-refactor-20260528`
- DYEC status before this ledger: clean.
- Latest DayOA semver tag before implementation: `2.0.18`; default next release tag is `2.0.19`.
- Runtime bucket/prefix checks:
  - `aws s3 ls s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/read_haps/ --profile lsmc --region us-west-2` -> rc `1`, no listing.
  - `aws s3 ls s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/charr/ --profile lsmc --region us-west-2` -> rc `1`, no listing.
- Assumptions:
  - DayOA owns code, tests, docs, ledger, and release tag for this work.
  - DYEC remains a clean access/control repo unless runtime validation requires tracked DYEC changes.
  - Live S3 runtime-asset publication is approved by the accepted plan and is non-destructive; no object deletion or tag rewriting is in scope.
  - Low-depth `site_mix` behavior remains out of scope and should continue to fail/report explicitly when no usable sites are available.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| EU-001 | Ledger | Create durable DayOA ledger with Gate 0 inventory before implementation | SUCCESS | feature_implementation | Gate 0 | orchestrator | This file records repo paths, branches, dirty files, tag baseline, and runtime prefix checks. |  | Ledger created before workflow code edits for this plan. |
| EU-002 | Kraken2 | Zero human-unmapped reads skip Kraken2 execution and emit explicit sentinel native/MQC evidence | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/unmapped_metagenomics.smk`; `workflow/scripts/summarize_unmapped_metagenomics.py`; `tests/test_unmapped_metagenomics.py`; focused suite -> `53 passed`. |  | Kraken2 now validates config/DB first, rejects malformed FASTQ, emits zero-read sentinel report/output/MQC only when extracted FASTQ has zero reads, and keeps strict non-empty behavior. |
| EU-003 | Ganon2 | Zero human-unmapped reads skip Ganon2 execution and emit explicit sentinel native/MQC evidence | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/unmapped_metagenomics.smk`; `workflow/scripts/summarize_unmapped_ganon2.py`; `tests/test_unmapped_metagenomics.py`; focused suite -> `53 passed`. |  | Ganon2 now validates configured prefixes first, rejects malformed FASTQ, emits `.tre`, `.rep`, and MQC zero-read sentinels only when extracted FASTQ has zero reads, and keeps strict non-empty behavior. |
| EU-004 | sourmash | Zero human-unmapped reads skip sourmash execution and emit explicit sentinel native/MQC evidence | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/unmapped_metagenomics.smk`; `workflow/scripts/summarize_unmapped_sourmash.py`; `tests/test_unmapped_metagenomics.py`; focused suite -> `53 passed`. |  | sourmash now validates configured databases first, rejects malformed FASTQ, emits minimal signature/gather/MQC zero-read sentinels only when extracted FASTQ has zero reads, rejects zero-read sentinel signatures for non-empty FASTQs, and keeps strict non-empty behavior. |
| EU-005 | Tests | Add focused local tests for zero-read sentinel behavior, malformed FASTQ rejection, and non-empty strictness | SUCCESS | contract_test | Gate 5 | orchestrator | `python -m pytest -q tests/test_unmapped_metagenomics.py tests/test_multiqc_staging_contracts.py tests/test_multiqc_qc_targets.py tests/test_contam_identity_bundle.py` -> `53 passed`; `python -m pytest -q` -> `231 passed`; `python -m py_compile workflow/scripts/summarize_unmapped_metagenomics.py workflow/scripts/summarize_unmapped_ganon2.py workflow/scripts/summarize_unmapped_sourmash.py workflow/scripts/compile_contam_identity_mqc.py workflow/scripts/run_charr_contam.py` -> pass; `git diff --check` -> pass. |  | Local implementation and contract tests pass. |
| EU-006 | Runtime assets | Locate or create real read_haps and CHARR runtime assets with provenance and publish to configured S3 prefixes | AMENDED | feature_implementation | Gate 5 | orchestrator | read_haps upstream cloned from `https://github.com/DecodeGenetics/read_haps.git` at `983e15c409cbf0b7d5eb87cec20085149f62de08`; `high_quality_markers_deCODE_2015.txt.gz` sha256 `5ebd2c66c5f083e4d1d6899309eeb4b9e099ee7cb761cc8dc92f5a8d8f6c78ea`; uploaded file, sha256, and provenance to `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/read_haps/`. | User requested CHARR retirement before final validation. | read_haps asset published; CHARR runtime asset publication no longer required because active DayOA no longer includes or requests CHARR. |
| EU-007 | Cluster validation | Verify runtime assets on FSx and rerun DayOA dry-run/live workflow with `--rerun-triggers mtime` | SUCCESS | contract_test | Gate 5 | orchestrator | Headnode run id `dayoa_2017_hg002_kitchensink_j200_readhapsfix2_151101`; dry run `DAYOA_2017_HG002_READHAPSFIX2_DRYRUN_RC=0`; live run `DAYOA_2017_HG002_READHAPSFIX2_LIVE_RC=0`; final report `results/day/hg38/reports/DAY_final_multiqc.html`; evidence manifest `results/day/hg38/reports/dayoa_evidence_manifest.json`; final Snakemake log `.snakemake/log/2026-05-28T151145.748533.snakemake.log`. |  | HG002 kitchensink restart completed final MultiQC with workflow return code 0. |
| EU-008 | Release | Commit all intended DayOA changes, push branch, create non-`v` annotated release tag, and push tag | OPEN | feature_implementation | Gate 5 | orchestrator | Pending. |  |  |
| EU-009 | CHARR runtime recipe | Replace broken CHARR conda recipe with the tested Hail runtime recipe | SUPERSEDED | plan_amendment | Gate 2 | orchestrator | Public package/container check found no standalone CHARR conda/container; later user instruction retired CHARR from active DayOA instead of repairing the runtime. | CHARR remained a runtime blocker and was not needed for this validation after user-directed retirement. | CHARR env/script/rules/config outputs were removed from active DayOA surfaces instead of carrying a CHARR runtime recipe forward. |

## 2026-05-28T15:17Z Cluster Restart Evidence

- Plan amendment: CHARR is retired rather than repaired. Active Snakemake includes, requested outputs, final MultiQC staging, custom-data config, rule-config templates, and docs no longer request CHARR outputs. The generated local profile was also cleaned of its stale CHARR block.
- Headnode DayOA checkout: `/fsx/analysis_results/ubuntu/2.0.17/daylily-omics-analysis`.
- Controller tmux session: `dayoa_2017_hg002_kitchensink_j200_zeroread_144306`.
- Latest restart run id: `dayoa_2017_hg002_kitchensink_j200_readhapsfix2_151101`.
- Dry-run command used `--rerun-triggers mtime -j 200 -p -k -n`; result: `DAYOA_2017_HG002_READHAPSFIX2_DRYRUN_RC=0`.
- Live command used the same command without `-n`; result: `DAYOA_2017_HG002_READHAPSFIX2_LIVE_RC=0`.
- Live Snakemake completion evidence: `9 of 9 steps (100%) done`, `WORKFLOW SUCCESS`, `RETURN CODE: 0`, complete log `.snakemake/log/2026-05-28T151145.748533.snakemake.log`.
- Final report evidence:
  - `results/day/hg38/reports/DAY_final_multiqc.html`, 5.1M, timestamp `2026-05-28 15:17`.
  - `results/day/hg38/reports/dayoa_evidence_manifest.json`, 51K, timestamp `2026-05-28 15:17`.
  - `results/day/hg38/reports/multiqc_inputs/final/manifest.tsv`, 115K.
- Final manifest checks:
  - `grep -i charr results/day/hg38/reports/multiqc_inputs/final/manifest.tsv` returned no rows.
  - Manifest contains `haplocheck_native` and `read_haps_native`, preventing collisions with `haplocheck_mtdna_mqc.tsv` and `read_haps_mqc.tsv`.
  - Manifest includes Kraken2, Ganon2, sourmash, GIAB concordance, relatedness, contamination, VEP, ExpansionHunter, HTD, Haplocheck, and read_haps evidence rows.
- Queue state after completion: `squeue -u ubuntu` returned only the header; no HG002 Slurm jobs remained.
- Non-fatal residual warning: MultiQC logged a `goleft_indexcov` duplicate-sample module warning for `sent.dmd` and `sent.na` staged native goleft files, but MultiQC still wrote the final report and Snakemake exited `0`.
- Local focused validation after mirroring the read_haps staging collision fix: `python -m pytest -q tests/test_multiqc_sample_identifiers.py tests/test_multiqc_staging_contracts.py tests/test_contam_identity_bundle.py tests/test_multiqc_qc_targets.py` -> `59 passed`.
