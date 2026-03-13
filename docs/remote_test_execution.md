# Remote Test Execution Guide

## Overview
This document captures the patterns for running daylily pipeline tests remotely on the AWS ParallelCluster headnode via SSH and tmux.

## Prerequisites
- SSH access to headnode: `ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@<HEADNODE_IP>`
- Analysis directories created via `day-clone`
- Manifest files (`samples.tsv`, `units.tsv`) in place

## Key Command Pattern

**Critical**: Use `&&` chaining with explicit paths. The `day_activate` script uses `return` which breaks multi-line bash scripts but works in chained commands.

```bash
cd /fsx/analysis_results/ubuntu/<ANALYSIS_DIR>/daylily-omics-analysis && \
. ~/.bashrc && \
. dyoainit && \
source bin/day_activate slurm hg38 && \
bin/day_run <TARGETS> <FLAGS> 2>&1 | tee /tmp/<SESSION_NAME>.log
```

## Creating Tmux Sessions

### Single Session Creation
```bash
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@<HEADNODE_IP> '
source ~/.bashrc
tmux new-session -d -s <SESSION_NAME>
tmux send-keys -t <SESSION_NAME> "cd <ANALYSIS_DIR> && . ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38 && bin/day_run <TARGETS> <FLAGS> 2>&1 | tee /tmp/<SESSION_NAME>.log" Enter
'
```

### Batch Session Creation Example
```bash
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@<HEADNODE_IP> '
source ~/.bashrc

# Kill existing sessions if needed
for sess in test-ilmn-5x-run test-ont-5x-run test-pb-5x-run; do
  tmux kill-session -t $sess 2>/dev/null
done

# Illumina 5x
tmux new-session -d -s test-ilmn-5x-run
tmux send-keys -t test-ilmn-5x-run "cd /fsx/analysis_results/ubuntu/test-ilmn-5x-dry/daylily-omics-analysis && . ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38 && bin/day_run produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf produce_alignstats dedup_doppelmark -p -k -j 10 -T 1 2>&1 | tee /tmp/test-ilmn-5x-run.log" Enter

echo "Created sessions"
tmux ls
'
```

## Target Rules by Platform

### Single-Platform Workflows

| Platform | Targets | Notes |
|----------|---------|-------|
| **Illumina** (FASTQ) | `produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf produce_alignstats dedup_doppelmark` | Needs alignment + dedup + calling |
| **ONT** (pre-aligned) | `produce_snv_concordances produce_alignstats` | CRAM input, uses cram aligners |
| **PacBio** (pre-aligned) | `produce_snv_concordances produce_alignstats` | CRAM input |
| **Ultima** (pre-aligned) | `produce_snv_concordances produce_alignstats` | CRAM input |

### Hybrid Workflows (Monolithic CLI-based)

| Workflow | Targets | Notes |
|----------|---------|-------|
| **Illumina+ONT** | `produce_sentdhio_vcf produce_alignstats produce_snv_concordances` | Uses sentdhio (sentieon-cli) |
| **Ultima+ONT** | `produce_sentdhuo_vcf produce_alignstats produce_snv_concordances` | Uses sentdhuo (sentieon-cli) |

### Hybrid Workflows (Modular - NEW)

| Workflow | Targets | Notes |
|----------|---------|-------|
| **Illumina+ONT** | `produce_sentdhiom_vcf produce_alignstats produce_snv_concordances` | Uses sentdhiom (modular rules) |
| **Ultima+ONT** | `produce_sentdhuom_vcf produce_alignstats produce_snv_concordances` | Uses sentdhuom (modular rules) |

## Common Flags

| Flag | Description |
|------|-------------|
| `-p` | Print shell commands |
| `-k` | Keep going on errors |
| `-j N` | Max N parallel jobs (slurm: 10-500, local: 1-2) |
| `-n` | Dry-run only |
| `-T 1` | Max 1 retry per job |

## Monitoring

### Check Slurm Queue
```bash
ssh ... 'source ~/.bashrc && /opt/slurm/bin/squeue -u ubuntu --format="%.10i %.50j %.8T %.12M"'
```

### Check Tmux Session Output
```bash
ssh ... 'source ~/.bashrc && tmux capture-pane -t <SESSION_NAME> -p | tail -30'
```

### Check All Sessions
```bash
ssh ... 'source ~/.bashrc && for sess in $(tmux ls -F "#{session_name}"); do echo "=== $sess ==="; tmux capture-pane -t $sess -p | tail -10; done'
```

### Check Log Files
```bash
ssh ... 'source ~/.bashrc && tail -50 /tmp/<SESSION_NAME>.log'
```

## Troubleshooting

### Common Issues

1. **"unrecognized arguments"**: Check snakemake flag names (`-T` not `--attempts`)
2. **MissingInputException**: Ensure upstream targets are included (e.g., alignment before concordance)
3. **YAML parse errors**: Check for unresolved git merge conflicts in config files
4. **conda not found**: Ensure `. ~/.bashrc` is first in command chain
5. **BAM index format**: ONT needs `.csi` indexes, not `.bai`

### Index Creation for ONT
```bash
samtools index -c /path/to/file.bam  # Creates .bam.csi
```

