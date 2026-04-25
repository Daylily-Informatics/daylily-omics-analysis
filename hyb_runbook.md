> **Historical run note.** This file records a specific hybrid/Ultima rerun plan and verified S3 paths. For current target and launch patterns, use [`COMMANDS_MUST_RUN.md`](COMMANDS_MUST_RUN.md) and [`docs/remote_test_execution.md`](docs/remote_test_execution.md).

# Hybrid And Ultima Rerun Runbook

This runbook records two verified Daylily omics rerun examples and the `mk-gotime3` launch handoffs for running trimmed-manifest reruns. Do not perform destructive AWS actions. Do not add fallback behavior. If any required command fails, stop loudly and report the failure.

## Verified ILMN+ONT Hybrid Run: `take1`

Run root:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/
```

Results:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/results/day/hg38_broad/
```

Manifest locations:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/config/samples.tsv
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/config/units.tsv
```

Observed Snakemake command:

```bash
snakemake --profile=/fsx/analysis_results/ubuntu/take1/daylily-omics-analysis/config/day_profiles/slurm produce_snv_concordances produce_sentdhiom_sv produce_sentdhiom_vcf -p -j 100 -k
```

Input data prefixes:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/
```

Concise manifest example:

- `samples.tsv`: one `HG003` positive-control sample with GIAB truth data under `/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/`.
- `units.tsv`: `HIOa/HG003` units with `SR20x-ONT7x`, `SR20x-ONT10x`, `SR20x-ONT15x`, `SR30x-ONT7x`, `SR30x-ONT10x`, and `SR30x-ONT15x`.

## Verified Solo Ultima Genomics Run: `agbt_ug`

Run root:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/
```

Results:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/results/day/hg38_broad/
```

Manifest and command-log locations:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/samples.tsv
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/units.tsv
s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/day_cmd.log
```

Observed Snakemake command:

```bash
snakemake --profile=/fsx/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/day_profiles/slurm produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1
```

Input data prefix:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/
```

Verified input CRAMs:

```text
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_1x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_3x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_5x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_7x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_10x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_15x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_20x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_30x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_40x.cleaned.cram
s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_50x.cleaned.cram
```

Concise manifest example:

- `samples.tsv`: one `HG003` positive-control sample with GIAB truth data under `/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/`.
- `units.tsv`: `Ug1/HG003` at `1x`, `3x`, `5x`, `7x`, `10x`, `15x`, `20x`, `30x`, `40x`, and `50x`.
- Each Ultima unit uses `SEQ_VENDOR=UG`, `SEQ_PLATFORM=ULTIMA`, `ULTIMA_CRAM_ALIGNER=ug`, and `ULTIMA_CRAM_SNV_CALLER=ug`.

## Shared `mk-gotime3` Launch Pattern

Use `AWS_PROFILE=lsmc` and Daylily's supported SSM headnode entrypoint:

```bash
cd /Users/jmajor/projects/daylily/daylily-ephemeral-cluster
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
AWS_PROFILE=lsmc daylily-ec headnode connect --profile lsmc --region us-west-2 --cluster mk-gotime3
```

Inside the SSM shell, launch each pipeline in its own persistent, well named tmux session. Do not close or kill the sessions after launch. Detach with `Ctrl-b`, then `d`.

For every rerun:

- Clone with `day-clone -t main -d <analysis_code>`, where `<analysis_code>` matches the S3 analysis code.
- Stage `samples.tsv` and `units.tsv` from that run's S3 config paths into `./config`.
- Keep only lines 1-4 in `./config/units.tsv`.
- Activate `slurm hg38_broad`.

```bash
awk 'NR <= 4' ./config/units.tsv > ./config/units.tsv.tmp
mv ./config/units.tsv.tmp ./config/units.tsv
wc -l ./config/units.tsv

source dyoainit
dy-a slurm hg38_broad
```

## Hybrid `take1` Launch Handoff

Persistent tmux session:

```bash
tmux new-session -s take1_hiom_rerun_20260422
```

Commands inside tmux:

```bash
set -euo pipefail
day-clone -t main -d take1
cd /fsx/analysis_results/ubuntu/take1/daylily-omics-analysis

mkdir -p config
aws s3 cp s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/config/samples.tsv ./config/samples.tsv
aws s3 cp s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/config/units.tsv ./config/units.tsv

awk 'NR <= 4' ./config/units.tsv > ./config/units.tsv.tmp
mv ./config/units.tsv.tmp ./config/units.tsv
wc -l ./config/units.tsv

source dyoainit
dy-a slurm hg38_broad
dy-r produce_snv_concordances produce_sentdhiom_sv produce_sentdhiom_vcf -p -j 100 -k &
```

Verification before reporting back:

```bash
tmux has-session -t take1_hiom_rerun_20260422
cd /fsx/analysis_results/ubuntu/take1/daylily-omics-analysis
wc -l config/units.tsv
tail -n 20 day_cmd.log
command -v squeue
squeue -u ubuntu
```

Report back:

- tmux session name: `take1_hiom_rerun_20260422`
- attach command inside SSM: `tmux attach -t take1_hiom_rerun_20260422`
- `units.tsv` line count
- latest `day_cmd.log` command line
- current `squeue -u ubuntu` summary

## Ultima `agbt_ug` Launch Handoff

Persistent tmux session:

```bash
tmux new-session -s agbt_ug_ultima_rerun_20260422
```

Commands inside tmux:

```bash
set -euo pipefail
day-clone -t main -d agbt_ug
cd /fsx/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis

mkdir -p config
aws s3 cp s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/samples.tsv ./config/samples.tsv
aws s3 cp s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/units.tsv ./config/units.tsv

awk 'NR <= 4' ./config/units.tsv > ./config/units.tsv.tmp
mv ./config/units.tsv.tmp ./config/units.tsv
wc -l ./config/units.tsv

source dyoainit
dy-a slurm hg38_broad
dy-r produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 &
```

Verification before reporting back:

```bash
tmux has-session -t agbt_ug_ultima_rerun_20260422
cd /fsx/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis
wc -l config/units.tsv
tail -n 20 day_cmd.log
command -v squeue
squeue -u ubuntu
```

Report back:

- tmux session name: `agbt_ug_ultima_rerun_20260422`
- attach command inside SSM: `tmux attach -t agbt_ug_ultima_rerun_20260422`
- `units.tsv` line count
- latest `day_cmd.log` command line
- current `squeue -u ubuntu` summary
