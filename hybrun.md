# SSM Launch Plan For `take1` On `mk-gotime3`

## Summary
Use `AWS_PROFILE=lsmc` and Daylily’s supported SSM entrypoint to open an `ubuntu` bash login shell on `mk-gotime3`, create a persistent tmux session, clone `daylily-omics-analysis` from `main`, stage the verified hybrid manifests, trim `units.tsv` to lines 1-4, activate `slurm hg38_broad`, and launch the hybrid run in the tmux session.

Verified read-only:
- Profile: `lsmc`
- Account: `108782052779`
- Cluster: `mk-gotime3`
- Region: `us-west-2`
- Headnode instance: `i-061e067471c91714b`
- SSM command behind the helper: `aws ssm start-session --region us-west-2 --target i-061e067471c91714b --document-name SSM-SessionManagerRunShell`

## Execution
Open the SSM login shell:
```bash
cd /Users/jmajor/projects/daylily/daylily-ephemeral-cluster
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
AWS_PROFILE=lsmc daylily-ec headnode connect --profile lsmc --region us-west-2 --cluster mk-gotime3
```

Inside the SSM shell, create and enter a persistent tmux session:
```bash
tmux new-session -s take1_hiom_rerun_20260422
```

Inside tmux, run:
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

Detach from tmux with `Ctrl-b`, then `d`.

## Verification
Before reporting back, check from the same SSM shell or a new SSM shell:
```bash
tmux list-sessions
tmux has-session -t take1_hiom_rerun_20260422
cd /fsx/analysis_results/ubuntu/take1/daylily-omics-analysis
wc -l config/units.tsv
tail -n 20 day_cmd.log
command -v squeue
squeue -u ubuntu
```

Expected:
- `config/units.tsv` has exactly `4` lines.
- `day_cmd.log` includes the `dy-r`/Snakemake invocation.
- `squeue -u ubuntu` shows submitted jobs or a clear post-submit state.
- tmux session `take1_hiom_rerun_20260422` still exists after launch.

## Report Back
Return:
- tmux session name: `take1_hiom_rerun_20260422`
- reconnect command:
  ```bash
  AWS_PROFILE=lsmc daylily-ec headnode connect --profile lsmc --region us-west-2 --cluster mk-gotime3
  ```
- attach command inside SSM:
  ```bash
  tmux attach -t take1_hiom_rerun_20260422
  ```
- `units.tsv` line count.
- latest `day_cmd.log` command line.
- current `squeue -u ubuntu` summary.

## Assumptions
- Use `hg38_broad`, not `hg38-broad`.
- Use local `AWS_PROFILE=lsmc` for SSM access; remote S3 copies use the headnode’s configured AWS access/instance role.
- “Remove all lines > line 4” means keep header plus the first three unit rows.
- If `day-clone -t main -d take1` or any command fails, stop loudly; do not apply fallback behavior.
