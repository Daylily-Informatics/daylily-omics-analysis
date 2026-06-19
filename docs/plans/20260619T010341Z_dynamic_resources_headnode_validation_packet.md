# Dynamic Resources Headnode Validation Packet

Date: 2026-06-19T01:03:41Z

This packet is the remaining live validation for `docs/plans/20260619T003533Z_dynamic_resources_partition_ledger.md`.

## Local Access Blocker

The local Mac does not currently have a usable DAY-EC/headnode access path:

- `command -v daylily-ec` returned no executable.
- `command -v dyec` returned no executable.
- `aws sts get-caller-identity` returned `Unable to locate credentials`.
- AWS CLI is v1 on this Mac; `aws configure list-profiles` is not available.

Do not use direct SSH, PEM files, `pcluster ssh`, raw `snakemake`, or one-shot SSM workflow controllers to work around this.

## Required Headnode Preconditions

Run this only after connecting through the supported `daylily-ec`/SSM path:

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
AWS_PROFILE=<profile> daylily-ec headnode connect --profile <profile> --region <region> --cluster <cluster>
exec bash -l
```

Inside the resulting headnode shell:

```bash
id -un
echo "$0"
command -v day-clone
command -v tmux
command -v squeue
command -v sinfo
command -v scontrol
command -v aws
aws sts get-caller-identity --output json
```

Required acceptance:

- `id -un` prints `ubuntu`.
- A login-capable bash shell is active; if not, run `exec bash -l`.
- `tmux`, `squeue`, `sinfo`, `scontrol`, and `aws` are available.
- AWS identity succeeds under the intended read-only headnode role/profile.

## Repository State

Validate the exact commit/branch that contains the dynamic resource changes. If the work is still uncommitted locally, first commit/push or otherwise deploy the exact patch to the headnode using the repo's normal non-destructive deployment path.

After checkout on the headnode:

```bash
cd /fsx/analysis_results/ubuntu/<workset_code>/daylily-omics-analysis
git status --short --branch
python -m py_compile daylily_omics_analysis/slurm/spot_partition_order.py daylily_omics_analysis/workflow_resources.py
python -m pytest tests/test_dynamic_resource_helpers.py tests/test_slurm_caller_partitions.py tests/test_multiqc_qc_targets.py -q
```

## Live Partition Metadata Preflight

Use only real Slurm and AWS read-only metadata. This intentionally refreshes the partition-cost cache.

```bash
rm -f ~/.config/dayoa/partition_costs.log ~/.config/dayoa/partition_costs.log.lock
DAY_PROFILE=slurm AWS_REGION=<region> python -m daylily_omics_analysis.slurm.spot_partition_order i384nvme,i192nvme
test -s ~/.config/dayoa/partition_costs.log
head -n 2 ~/.config/dayoa/partition_costs.log
```

Required acceptance:

- The command exits 0.
- `~/.config/dayoa/partition_costs.log` exists with the expected TSV header.
- The two requested partitions have live median `usd_per_vcpu_hr` values.
- No static config catalog or fallback pricing source is used.

## DayOA Dry Runs

Use a persistent, single-pane tmux session. Send setup and execution as separate commands.

```bash
SESSION=dynamic_resources_partition_20260619
tmux new-session -d -s "$SESSION" 'bash -il'
tmux list-windows -t "$SESSION"
tmux list-panes -t "$SESSION"
tmux send-keys -t "$SESSION" 'cd /fsx/analysis_results/ubuntu/<workset_code>/daylily-omics-analysis' Enter
tmux send-keys -t "$SESSION" 'source dyoainit' Enter
tmux send-keys -t "$SESSION" 'dy-a slurm hg38' Enter
tmux send-keys -t "$SESSION" 'PARTITION_MAGIC=0 dy-r produce_bwa2a_align produce_dmd_dedup_cram produce_sentd_snv_vcf -p -k -j 1 -n' Enter
tmux capture-pane -pt "$SESSION" -S -200
tmux send-keys -t "$SESSION" 'dy-r produce_bwa2a_align produce_dmd_dedup_cram produce_sentd_snv_vcf -p -k -j 1 -n' Enter
tmux capture-pane -pt "$SESSION" -S -300
```

Required acceptance:

- The `PARTITION_MAGIC=0` dry-run passes and preserves configured partition order.
- The live partition-order dry-run passes and invokes dynamic partition ordering.
- No raw `snakemake` command is used.
- If either dry-run fails because of missing Slurm metadata or AWS permissions, preserve the exact pane output and keep the ledger row blocked.

## Ledger Closeout

Only after the headnode evidence above exists:

- Mark `PART-003` `SUCCESS` with the `sinfo`/`scontrol`/AWS evidence root.
- Mark `DRYRUN-001` `SUCCESS` with the tmux session name and captured dry-run evidence.
- If either command cannot run because of missing access/tooling, keep the row `BLOCKED` and record the exact missing command or permission.
