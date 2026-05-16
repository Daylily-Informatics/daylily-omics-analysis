# Remote Test Execution

This guide describes the supported pattern for running Daylily workflow tests on an AWS ParallelCluster headnode and leaving the run inspectable after the launching terminal disconnects.

## Access

Use brokered access through `daylily-ephemeral-cluster` and `daylily-ec`. Direct SSH, PEM files, and `pcluster ssh` are not supported access paths for these headnodes.

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
AWS_PROFILE=<profile> daylily-ec headnode connect \
  --profile <profile> \
  --region <region> \
  --cluster <cluster>
```

The resulting shell should be `ubuntu` running login `bash`. Verify:

```bash
id -un
echo "$0"
command -v day-clone
command -v tmux
command -v squeue
```

If the shell is not login `bash`, run `exec bash -l` before `day-clone`, `tmux`, `source dyoainit`, `dy-a`, or `dy-r`.

## Persistent Tmux Launch

Use one tmux session per workflow. Before interacting with an existing session, verify it has exactly one window and one pane:

```bash
window_count=$(tmux list-windows -t <session_name> -F '#{window_index}' | wc -l)
pane_count=$(tmux list-panes -a -F '#{session_name}' | awk '$1 == "<session_name>" {n++} END {print n + 0}')
test "$window_count" -eq 1
test "$pane_count" -eq 1
```

Create and initialize a workset one command at a time:

```bash
tmux new-session -d -s <session_name>
tmux send-keys -t <session_name> 'cd /fsx/analysis_results/ubuntu' Enter
tmux send-keys -t <session_name> 'day-clone -t <git_ref> -d <workset_code>' Enter
tmux send-keys -t <session_name> 'cd /fsx/analysis_results/ubuntu/<workset_code>/daylily-omics-analysis' Enter
tmux send-keys -t <session_name> 'mkdir -p config' Enter
tmux send-keys -t <session_name> 'source dyoainit' Enter
tmux send-keys -t <session_name> 'dy-a slurm hg38' Enter
tmux send-keys -t <session_name> 'dy-r <targets> -p -j 20 -k -T 1 -n' Enter
tmux send-keys -t <session_name> 'dy-r <targets> -p -j 20 -k -T 1 &' Enter
```

Use `daylily-ec` to stage reads and create or deliver `samples.tsv` and `units.tsv` for the workset before running production commands. Copying manifests from another completed run is a debugging operation and should use verified paths only.

Do not combine `source dyoainit`, `dy-a`, and `dy-r` into one parsed shell line in tmux. The activation commands define shell functions and completion in the current shell.

## Monitoring

Use this order:

1. verify tmux shape
2. `squeue -u ubuntu`
3. `ps -fu ubuntu | grep -E 'snakemake|day_run|dy-r'`
4. latest `.snakemake/log/*.snakemake.log`
5. newest relevant `logs/slurm/<rule>/*.{out,err}`
6. stable rule log under `results/day/<build>/<sample>/.../logs/`

From an already connected SSM headnode shell, active compute nodes can be inspected by node name when Slurm shows a job there:

```bash
ssh <node-name> "bash -l -c 'df -h /dev/shm; free -g; uptime; ps -fu ubuntu | grep -E \"sentieon|samtools|mbuffer|day_run|snakemake\" | grep -v grep'"
```

Only inspect or control jobs for the workset under test. Do not cancel unrelated Slurm jobs.

## Common Target Sets

| Workflow | Targets |
| --- | --- |
| Illumina SNV/concordance | `produce_sent_align produce_dmd_dedup_cram produce_sentd_snv_vcf produce_snv_concordances produce_alignstats` |
| Complete Genomics/MGI | `produce_sentcg_align produce_smd_dedup_cram produce_cgt7p_snv_vcf produce_alignstats produce_snv_concordances` |
| ONT | `produce_sentmm2ont_align produce_na_dedup_cram produce_sentdont_snv_vcf produce_alignstats produce_snv_concordances` |
| PacBio | `produce_sentmm2_align produce_na_dedup_cram produce_sentdpb_snv_vcf produce_alignstats produce_snv_concordances` |
| Ultima | `produce_na_dedup_cram produce_sentdug_snv_vcf produce_alignstats produce_snv_concordances` |
| Hybrid Illumina+ONT modular | `produce_sentdhiom_snv_vcf produce_sentdhiom_sv produce_alignstats produce_snv_concordances` |
| Hybrid Ultima+ONT modular | `produce_sentdhuom_snv_vcf produce_alignstats produce_snv_concordances` |

Dry-run first with `-n`.
