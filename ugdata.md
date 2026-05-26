> **Historical run note.** This file records a specific mk-gotime3 planning session and S3 evidence. For current target and launch patterns, use [`COMMANDS_MUST_RUN.md`](COMMANDS_MUST_RUN.md) and [`docs/remote_test_execution.md`](docs/remote_test_execution.md). Do not reuse embedded command blocks verbatim when they conflict with current `daylily-ec`/SSM access or `dyoainit` activation guidance.

# 8-Agent Plan For `hyb_runbook.md` And `mk-gotime3` Reruns

## Objective

Coordinate three deliverables without changing the verified run facts:

- Create `/Users/jmajor/projects/daylily/daylily-omics-analysis/hyb_runbook.md` as a compact rerun runbook with two verified examples:
  - ILMN+ONT hybrid: `take1`
  - Solo Ultima Genomics: `agbt_ug`
- Execute-plan handoff for the hybrid `take1` rerun on `mk-gotime3`.
- Execute-plan handoff for the Ultima `agbt_ug` rerun on `mk-gotime3`.

Both examples were verified read-only against S3 using `AWS_PROFILE=daylily-service-lsmc`. The cluster execution handoff uses `AWS_PROFILE=lsmc`, SSM login to the headnode as `ubuntu`, persistent tmux sessions, `day-clone`, S3 manifest staging, first-4-lines `units.tsv`, `dyoainit`, `dy-a`, and `dy-r`.

Do not perform destructive AWS actions. Do not add fallback behavior. If any required command fails, stop loudly and report the failure.

## Required Runbook Content

The final `hyb_runbook.md` must include these sections and facts.

### ILMN+ONT Hybrid Run

- Run root: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/`
- Results: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/results/day/hg38_broad/`
- Manifest locations:
  - `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/config/samples.tsv`
  - `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260309T122755Z/analysis_results/ubuntu/take1/daylily-omics-analysis/config/units.tsv`
- Snakemake command:

```bash
snakemake --profile=/fsx/analysis_results/ubuntu/take1/daylily-omics-analysis/config/day_profiles/slurm produce_snv_concordances produce_sentdhiom_sv produce_sentdhiom_vcf -p -j 100 -k
```

- Input data prefixes:
  - ILMN FASTQs: `s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/`
  - ONT CRAMs: `s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/`
- Concise manifest example:
  - `samples.tsv`: one `HG003` positive-control sample with GIAB truth data under `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/`
  - `units.tsv`: `HIOa/HG003` units with `SR20x-ONT7x`, `SR20x-ONT10x`, `SR20x-ONT15x`, `SR30x-ONT7x`, `SR30x-ONT10x`, and `SR30x-ONT15x`

### Solo Ultima Genomics Run

- Run root: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/`
- Results: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/results/day/hg38_broad/`
- Manifest and command-log locations:
  - `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/samples.tsv`
  - `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/units.tsv`
  - `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/day_cmd.log`
- Snakemake command:

```bash
snakemake --profile=/fsx/analysis_results/ubuntu/agbt_ug/daylily-omics-analysis/config/day_profiles/slurm produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1
```

- Input data prefix: `s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/`
- Verified input CRAMs:

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

- Concise manifest example:
  - `samples.tsv`: one `HG003` positive-control sample with GIAB truth data under `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/`
  - `units.tsv`: `Ug1/HG003` at `1x`, `3x`, `5x`, `7x`, `10x`, `15x`, `20x`, `30x`, `40x`, and `50x`
  - Each Ultima unit uses `SEQ_VENDOR=UG`, `SEQ_PLATFORM=ULTIMA`, `ULTIMA_CRAM_ALIGNER=ug`, and `ULTIMA_CRAM_SNV_CALLER=ug`

## Shared `mk-gotime3` Execution Pattern

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
- Keep only lines 1-4 in `./config/units.tsv`:

```bash
awk 'NR <= 4' ./config/units.tsv > ./config/units.tsv.tmp
mv ./config/units.tsv.tmp ./config/units.tsv
wc -l ./config/units.tsv
```

- Initialize and activate:

```bash
source dyoainit
dy-a slurm hg38_broad
```

## Hybrid `take1` Execution Plan

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

Hybrid verification before reporting back:

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

## Ultima `agbt_ug` Execution Plan

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

Ultima verification before reporting back:

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

## Agent Plan

### Agent 1: Instruction And Repo-State Auditor

Responsibility:
- Read active repo instructions and confirm whether the current task is documentation-only or cluster execution.
- Check `git status --short`.
- Identify unrelated existing dirty files and ensure they are not touched.
- Confirm `mk-gotime3`, `us-west-2`, and `AWS_PROFILE=lsmc` for execution handoffs.

Required handoff:
- Repo root path.
- Current `git status --short` summary.
- Confirmation that the documentation target is `hyb_runbook.md`.
- Confirmation that cluster execution, if requested, uses SSM on `mk-gotime3` and performs no destructive AWS actions.

### Agent 2: Hybrid `take1` S3, Command, And Execution Verifier

Responsibility:
- Verify the `take1` run root, result prefix, manifest paths, and command-log evidence from the inventory or S3.
- Confirm the real non-dry-run Snakemake command exactly as listed above.
- Preserve the hybrid execution sequence from `hybrun.md`.

Required handoff:
- Verified `take1` run root.
- Verified `take1` result prefix.
- Verified `take1` manifest S3 paths.
- Exact `take1` Snakemake command.
- Hybrid tmux session name: `take1_hiom_rerun_20260422`.
- Hybrid `day-clone -t main -d take1` command and run directory.

### Agent 3: Hybrid Manifest Extractor

Responsibility:
- Read `take1` `samples.tsv` and `units.tsv` read-only from S3.
- Extract a concise example, not the full table unless needed for clarity.
- Preserve the sample and unit facts listed in this plan.
- Confirm the execution plan trims `units.tsv` to lines 1-4 before launching.

Required handoff:
- `samples.tsv` summary for `HG003`.
- `units.tsv` summary for `HIOa/HG003`.
- Coverage labels: `SR20x-ONT7x`, `SR20x-ONT10x`, `SR20x-ONT15x`, `SR30x-ONT7x`, `SR30x-ONT10x`, `SR30x-ONT15x`.
- Confirmation that runtime `config/units.tsv` is trimmed with `awk 'NR <= 4'`.

### Agent 4: Hybrid Input Data Prefix And Runtime Check Verifier

Responsibility:
- Verify or preserve the hybrid input-data prefixes exactly.
- Confirm they correspond to `/fsx/references/...` paths used by the exported manifests.
- Define the hybrid post-launch checks.

Required handoff:
- ILMN prefix: `s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/`
- ONT prefix: `s3://lsmc-dayoa-omics-analysis-us-west-2/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/`
- Hybrid checks: tmux session exists, `wc -l config/units.tsv`, latest `day_cmd.log`, and `squeue -u ubuntu`.

### Agent 5: Ultima `agbt_ug` S3, Command, And Execution Verifier

Responsibility:
- Verify the `agbt_ug` run root, result prefix, manifest paths, and command-log evidence from the inventory or S3.
- Confirm the real non-dry-run Snakemake command exactly as listed above.
- Define the Ultima execution sequence using the same process as hybrid.

Required handoff:
- Verified `agbt_ug` run root.
- Verified `agbt_ug` result prefix.
- Verified `agbt_ug` `samples.tsv`, `units.tsv`, and `day_cmd.log` S3 paths.
- Exact `agbt_ug` Snakemake command.
- Ultima tmux session name: `agbt_ug_ultima_rerun_20260422`.
- Ultima `day-clone -t main -d agbt_ug` command and run directory.

### Agent 6: Ultima Manifest, CRAM, And Runtime Check Verifier

Responsibility:
- Read `agbt_ug` `samples.tsv` and `units.tsv` read-only from S3.
- Preserve the exact verified CRAM list.
- Extract concise manifest examples.
- Confirm the execution plan trims `units.tsv` to lines 1-4 before launching.
- Define the Ultima post-launch checks.

Required handoff:
- `samples.tsv` summary for `HG003`.
- `units.tsv` summary for `Ug1/HG003`.
- Coverage labels: `1x`, `3x`, `5x`, `7x`, `10x`, `15x`, `20x`, `30x`, `40x`, `50x`.
- The full verified CRAM list from this plan.
- Confirmation that each Ultima unit uses `SEQ_VENDOR=UG`, `SEQ_PLATFORM=ULTIMA`, `ULTIMA_CRAM_ALIGNER=ug`, and `ULTIMA_CRAM_SNV_CALLER=ug`.
- Ultima checks: tmux session exists, `wc -l config/units.tsv`, latest `day_cmd.log`, and `squeue -u ubuntu`.

### Agent 7: `hyb_runbook.md` And Execution Section Assembler

Responsibility:
- Create `/Users/jmajor/projects/daylily/daylily-omics-analysis/hyb_runbook.md`.
- Assemble a compact Markdown runbook from the handoffs.
- Include clear sections for the hybrid and Ultima examples.
- Include exact S3 paths and Snakemake commands in fenced code blocks.
- Include concise manifest examples rather than full manifest tables.
- Include the shared `mk-gotime3` SSM/tmux execution pattern and both rerun command blocks.

Required handoff:
- Draft `hyb_runbook.md`.
- Confirmation that both examples are present.
- Confirmation that both execution handoffs are present.
- Confirmation that all required paths, commands, tmux names, clone destinations, and `units.tsv` trim commands are included exactly.

### Agent 8: QA Reviewer

Responsibility:
- Review `hyb_runbook.md` and execution handoffs against this plan.
- Confirm requirement preservation and path/command correctness.
- Check that both runs use persistent tmux sessions on `mk-gotime3`.
- Check that both runs stage `samples.tsv` and `units.tsv` from S3.
- Check that both runs trim `units.tsv` to the first 4 lines.
- Check that no fallback behavior or destructive AWS action was introduced.

Required handoff:
- QA pass/fail result.
- Any required edits, limited to preserving this plan's objectives.
- Final confirmation that:
  - `take1` is documented and has a launch handoff.
  - `agbt_ug` is documented and has a launch handoff.
  - The hybrid command is exact.
  - The Ultima command is exact.
  - The tmux sessions are `take1_hiom_rerun_20260422` and `agbt_ug_ultima_rerun_20260422`.
  - Both execution handoffs use `AWS_PROFILE=lsmc`, `dy-a slurm hg38_broad`, and `awk 'NR <= 4'`.

## Acceptance Checks

Run these checks after updating this plan or writing `hyb_runbook.md`:

```bash
rg -n "take1_hiom_rerun_20260422|agbt_ug_ultima_rerun_20260422|AWS_PROFILE=lsmc|day-clone -t main -d take1|day-clone -t main -d agbt_ug|awk 'NR <= 4'|dy-a slurm hg38_broad|produce_sentdhiom_sv|produce_sentdug_vcf" ugdata.md
```

Expected:

- Both tmux session names appear.
- Both `day-clone` commands use the S3 analysis codes: `take1` and `agbt_ug`.
- Both runs stage `samples.tsv` and `units.tsv` from S3.
- Both runs trim `units.tsv` to the first 4 lines.
- Both runs use persistent tmux sessions on `mk-gotime3`.
- No fallback behavior is introduced.

## Assumptions

- `mk-gotime.md cluster` means `mk-gotime3`.
- `agbt_ug` is the S3 analysis code and therefore the clone destination for the Ultima run.
- Ultima uses `hg38_broad`, matching the verified `agbt_ug` result prefix.
- This plan replaces `ugdata.md` in place.
- The final target document remains `/Users/jmajor/projects/daylily/daylily-omics-analysis/hyb_runbook.md`.
- The multi-agent count remains exactly 8 agents.
