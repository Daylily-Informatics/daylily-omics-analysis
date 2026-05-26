# HG003 HIOMR 1.0.22 Multiagent Restart Execution Ledger

Created: 2026-05-26T02:33:34Z

## Objective

Run the corrected DayOA `1.0.22` HIOMR campaign on `hyb-hg003` using AWS profile `lsmc` in `us-west-2`: cancel current jobs/controllers, delete immediate children of `/fsx/analysis_results/ubuntu`, run corrected full-coverage HG003 ILMN+ONT HIOMR first, then run the downsample matrix serially except for the user-approved overlap gate below. Each successful workdir must be DRA-exported, byte-verified against S3, and deleted locally before the next dependent launch.

## Gate 0: Planned Live Context

- Cluster: `hyb-hg003`
- Region/profile: `us-west-2`, `lsmc`
- DayOA tag: `1.0.22`
- HIOMR empty-shard fix release: `1.0.23`
- Analysis root to clear: `/fsx/analysis_results/ubuntu`
- Preserve staged manifests and data under `/fsx/analysis_results/johnm`
- Staged manifest root: `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z`
- Export destination: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/`
- Remote review log: `/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log`
- Destructive approval: user explicitly requested implementation of the multiagent plan on 2026-05-25 America/Los_Angeles, including cancellation and deletion of `/fsx/analysis_results/ubuntu/*`.
- User-approved stagger: on 2026-05-25 America/Los_Angeles, user asked to check FSx space when the full run is far enough through its work and launch one downsample experiment if sufficient space is available. Threshold amended to 70% on 2026-05-25 America/Los_Angeles.

## Rows

| ID | Owner | Requirement | Status | Gate | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|
| GATE-000 | Orchestrator | Capture live queue, tmux sessions, `/fsx` usage, current workdirs, and staged manifest presence. | DONE | Gate 0 | 2026-05-26T02:34Z SSM review captured: `squeue -u ubuntu` empty, stale tmux inventory present, `/fsx` 8.8T size / 1.5T used / 7.3T available / 18%, immediate child `hg003a_altair3_hiomr_ilmn20x_ont10x_1021`, staged manifest pairs present under the planned manifest root. Full evidence in remote review log. | | Terminal. |
| CLEANUP-001 | Orchestrator | Cancel `ubuntu` Slurm jobs and kill active DayOA/Snakemake controllers. | DONE | Destructive Gate | 2026-05-26T02:35Z `scancel -u ubuntu` issued; post-check `squeue -u ubuntu` empty and no `snakemake` / `dy-r` / `day_run` controllers for `/fsx/analysis_results/ubuntu`. | | Terminal. |
| CLEANUP-002 | Orchestrator | Delete immediate children of `/fsx/analysis_results/ubuntu`, preserving the parent and `/fsx/analysis_results/johnm`. | DONE | Destructive Gate | 2026-05-26T02:35Z ran `find /fsx/analysis_results/ubuntu -maxdepth 1 -mindepth 1 -exec rm -rf -- {} +`; post-delete immediate-child listing empty; `/fsx` remained 8.8T size / 1.5T used / 7.3T available / 18%. | | Terminal. |
| FULL-001 | Agent A | Run corrected full-coverage HIOMR from `day-clone -t 1.0.22 -d hg003a_altair3_hiomr_full_1022`. | FAILED | Gate 1 | 2026-05-26T02:36Z launched tmux `hg003a_altair3_hiomr_full_1022`; staged `full_hiomr` manifests; command running under Snakemake with `-j 234`; 2026-05-26T02:37Z `squeue` showed Slurm jobs `2899` and `2900`, and controller PID `2964872` using `--profile .../config/day_profiles/slurm`; `day_cmd.log` recorded the required command. 2026-05-26T03:10Z heartbeat: Slurm job `2902` running `sentdhiomr_sr_align`, controller PID `2964872` still active, no `daylily.*_run` terminal marker yet; latest Snakemake log at `.snakemake/log/2026-05-26T023659.479429.snakemake.log` showed `13 of 750 steps (2%) done` at 2026-05-26T02:45:19Z. 2026-05-26T03:41Z heartbeat: no terminal marker, `/fsx` 8.8T size / 1.7T used / 7.1T available / 19%, full workdir 149G, controller PID `2964872` active, Snakemake progress reached `24 of 750 steps (3%) done`, with `sentdhiomr_pass1` and `sentdhiomr_mapq0_*` jobs active/configuring; stagger gate not met because FULL-001 is below 80%. 2026-05-26T03:45Z status: no terminal marker, `/fsx` still 7.1T available, full workdir 151G, Snakemake progress reached `100 of 750 steps (13%) done`, and active queue is now `sentdhiomr_pass1`, `sentdhiomr_stage1`, `sentdhiomr_stage2`, and `sentdhiomr_merge_beds`; stagger gate still not met. 2026-05-26T04:06Z status: no terminal marker, `/fsx` 8.8T size / 1.8T used / 7.1T available / 20%, full workdir 228G, controller PID `2964872` active, Snakemake progress reached `346 of 750 steps (46%) done`, active queue includes `sentdhiomr_pass2`, `sentdhiomr_stage3`, many `sentdhiomr_transfer`, `sentdhiomr_anno`, `sentdhiomr_model_apply`, and `sentdhiomr_concat_pass`; stagger gate still not met. 2026-05-26T04:10Z heartbeat: no terminal marker, `/fsx` 8.8T size / 1.8T used / 7.1T available / 20%, full workdir 229G, controller PID `2964872` active, Snakemake progress reached `473 of 750 steps (63%) done`, active queue dominated by `sentdhiomr_transfer` with annotation activity and one long `sentdhiomr_stage3`; stagger gate still not met. | See FAIL-001: `sentdhiomr_stage1` empty interval shards caused missing `stage1_hap.bed`. | Terminal failure; failed workdir preserved. |
| FULL-EXPORT-001 | Agent B | Export, verify, and delete full-coverage HIOMR workdir. | BLOCKED | Gate 2 | Blocked because FULL-001 produced `daylily.failed_run`; no export or deletion performed. | FULL-001 failed before success marker. | Preserve failed workdir. |
| DS-001 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn20x_ont10x_1022`. | IN_PROGRESS | Gate 3 | 2026-05-26T04:37Z 70% stagger gate passed: FULL-001 had no terminal marker, progress `528 of 750 steps`, `/fsx` 8.8T size / 1.8T used / 7.1T available / 20%, full workdir 230G, and only full-run Slurm job `3055` active. Launched tmux `hg003a_altair3_hiomr_ilmn20x_ont10x_1022`, staged `hiomr_ilmn20x_ont10x` manifests, started required `dy-r` command with `-j 234`; 2026-05-26T04:39Z DS-001 Snakemake controller PID `3044652` active and Slurm jobs `3425` and `3426` submitted. | | Awaiting successful marker and absence of `daylily.failed_run`. |
| DS-002 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn20x_ont7x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-003 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn20x_ont5x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-004 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn15x_ont10x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-005 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn15x_ont7x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-006 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn15x_ont5x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-007 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn10x_ont10x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-008 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn7x_ont7x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-009 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn7x_ont5x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| DS-010 | Agent A | Run/export/verify/delete `hg003a_altair3_hiomr_ilmn5x_ont5x_1022`. | OPEN | Gate 3 | Pending predecessor. | | |
| FAIL-001 | Agent C | Diagnose any failed run from Snakemake master log and latest Slurm logs; perform one focused rerun only when no source change is required. | IN_PROGRESS | Failure Gate | 2026-05-26T05:16Z FULL-001 failed with `daylily.failed_run` and `__RUN_RC__:1`; main log `.snakemake/log/2026-05-26T023659.479429.snakemake.log` reached `560 of 750 steps (75%) done` then exited. `sentdhiomr_stage1` failed for chunks `14`, `15`, `16`, `17-19`, and `20-25`; stage1 logs report `contig: 0 intervals 0 bases` and missing/empty `stage1_hap.bed`. The configured `pop-v20g41-20251216.vcf.gz` and `.tbi` exist, so that path is not the active root cause. | HIOMR stage1 does not tolerate empty per-shard interval sets for the combined upper-contig shards. | No rerun yet; DS-001 is the second analysis run and remains active. If DS-001 also fails, stop remaining runs/controllers and finish debugging before any further launch. |
| FINAL-001 | Agent D | Produce final report with run states, S3 paths, retained failures, and final FSx usage. | OPEN | Gate 5 | Pending matrix completion. | | |

## Run Contract

- SSM/daylily-ec only; no direct SSH.
- Every clone uses `day-clone -t 1.0.22`.
- Every workflow uses `dy-a slurm hg38_broad`.
- Every workflow command uses `dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 234 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8`.
- At most one downsample HIOMR workflow may be active at a time.
- User-approved stagger exception: when FULL-001 reaches at least 70% completion and `/fsx` has at least 2.0T available, Agent A may launch DS-001 before FULL-EXPORT-001 completes. Record `df -h /fsx`, `du -sh` for active workdirs, `squeue`, terminal-marker checks, and the DS-001 tmux launch in the review log before launch.
- A successful workdir is DRA-exported and byte-verified before local deletion.
- Failed workdirs are preserved for diagnosis.
- User policy as of 2026-05-26T05:17Z: DS-001 is the second analysis run; if it also fails, stop all remaining runs/controllers and complete root-cause debugging before any further workflow launch.

## Status Checkpoints

- 2026-05-26T04:31Z: FULL-001 still running with no `daylily.*_run` marker. `/fsx` 8.8T size / 1.8T used / 7.1T available / 20%; full workdir 229G. Snakemake controller PID `2964872` active. Queue down to Slurm job `3055` (`sentdhiomr_stage3`) running 36:15. Progress reached `528 of 750 steps (70%) done`; DS-001 stagger gate was not met under the prior 80% threshold.
- 2026-05-26T04:37Z: user amended stagger gate to 70%; gate passed with FULL-001 still clean at `528 of 750 steps`, `/fsx` 7.1T available, and only Slurm job `3055` active from FULL-001. DS-001 launched in tmux `hg003a_altair3_hiomr_ilmn20x_ont10x_1022`; by 2026-05-26T04:39Z DS-001 had an active Snakemake controller and Slurm jobs `3425` and `3426`.
- 2026-05-26T04:41Z: FULL-001 and DS-001 both still running with no terminal markers. `/fsx` 8.8T size / 1.8T used / 7.0T available / 20%; active workdirs: FULL-001 235G, DS-001 468M. Slurm jobs: DS-001 `3425` and `3426` configuring `pre_prep_ont_cram`; FULL-001 `3427` running `sentdhiomr_pass2`. Controllers active: FULL-001 PID `2964872`; DS-001 PID `3044652`. Progress: FULL-001 `529 of 750 steps (71%)`; DS-001 `4 of 751 steps (1%)`.
- 2026-05-26T04:55Z: FULL-001 and DS-001 still running with no terminal markers. `/fsx` 8.8T size / 1.8T used / 7.0T available / 20%; active workdirs: FULL-001 236G, DS-001 579M. Slurm jobs: FULL-001 `3458` configuring `sentdhiomr_transfer`; DS-001 `3430` running `sentdhiomr_sr_align`. Controllers active: FULL-001 PID `2964872`; DS-001 PID `3044652`. Progress: FULL-001 `556 of 750 steps (74%)`; DS-001 `14 of 751 steps (2%)`.

- 2026-05-26T05:17Z: FULL-001 failed. Evidence: `daylily.failed_run`, `/tmp/hg003a_altair3_hiomr_full_1022.rc` contained `__RUN_RC__:1`, main Snakemake log `.snakemake/log/2026-05-26T023659.479429.snakemake.log` reached `560 of 750 steps (75%) done` then exited. Root evidence points to `sentdhiomr_stage1` chunks `14`, `15`, `16`, `17-19`, and `20-25`: each stage1 log shows `contig: 0 intervals 0 bases` followed by missing/empty `stage1_hap.bed`; the configured pop VCF and index exist. DS-001 was still running with no terminal marker, Slurm job `3430` active, progress `14 of 751 steps (2%) done`, `/fsx` 7.0T available, workdirs FULL-001 236G and DS-001 57G. User policy recorded: if DS-001 also fails, stop all remaining runs/controllers and finish debugging before further launch.

- 2026-05-26T05:23Z: Code diagnosis refined: the failed FULL-001 chunks had zero-byte `merged_diff.bed` inputs, so this was not a pop-VCF/reference issue. Active `sentdhiomr_stage1` lacked the empty-`merged_diff.bed` branch already present in neighboring refactored hybrid rules. Local repo patch now adds that branch to `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk` and adds `test_sentdhiomr_stage1_handles_empty_merged_diff_beds`; targeted `pytest tests/test_snakemake_parser_contracts.py -q` passed (`4 passed`). DS-001 remains active on the old `1.0.22` launched code and is treated as the second run under the user stop policy.

- 2026-05-26T05:29Z: Preparing release `1.0.23` for the `sentdhiomr_stage1` empty-`merged_diff.bed` fix. Next remote workflow action is to update active analysis checkouts to the new tag, dry-run with `--rerun-triggers mtime -n`, confirm the dry-run does not restart unrelated completed work, then run without `-n` and debug any new failures.
