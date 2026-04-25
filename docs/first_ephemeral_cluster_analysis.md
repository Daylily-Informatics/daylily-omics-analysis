# First Ephemeral Cluster Analysis

This guide assumes `daylily-ephemeral-cluster` has already created a ParallelCluster headnode with FSx mounted at `/fsx`.

## Create A Workset

Use one workset directory per analysis. On the headnode:

```bash
cd /fsx/analysis_results/ubuntu
day-clone -t <git-ref-or-tag> -d <workset-name>
cd /fsx/analysis_results/ubuntu/<workset-name>/daylily-omics-analysis
```

Stage inputs:

```bash
mkdir -p config
cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv
```

For production runs, copy the intended `samples.tsv` and `units.tsv` into `config/`.

## Initialize And Run

Run initialization as separate shell commands. `dy-a` and `dy-r` are shell functions exposed after `source dyoainit`.

```bash
source dyoainit
dy-a slurm hg38

dy-r produce_snv_concordances -p -k -j 20 -n
dy-r produce_snv_concordances -p -k -j 20
```

For long-running work, run inside a named tmux session and leave the session attached to the workset.

## Monitoring Order

Read status in this order:

1. `squeue -u ubuntu`
2. headnode controller process: `ps -fu ubuntu | grep -E 'snakemake|day_run|dy-r'`
3. latest `.snakemake/log/*.snakemake.log` by mtime
4. newest relevant `logs/slurm/<rule>/*.{out,err}` by mtime
5. stable active rule log under `results/day/<build>/<sample>/.../logs/`

For active Slurm jobs, use the node name from `squeue` and inspect the compute node from the headnode:

```bash
ssh <node-name> "bash -l -c 'df -h /dev/shm; free -g; uptime; ps -fu ubuntu | grep -E \"sentieon|samtools|mbuffer|day_run|snakemake\" | grep -v grep'"
```

Do not touch unrelated Slurm jobs when debugging a single workset.

## Completion

A clean run writes `daylily.successful_run`. Results are under `results/day/<build>/`, aggregate reports under `results/day/<build>/other_reports/`, benchmark summaries under `results/day/<build>/reports/`, and logs under `.snakemake/log/` plus `logs/slurm/`.
