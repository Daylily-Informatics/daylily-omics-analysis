You are an expert data engineer working inside this repo in VS Code. Your task is to generate a telemetry dataset that can be joined to the existing benchmarking tables (consolidated_bench.tsv and consolidated_concordance.tsv) to enable prediction of compute time and cost by condition (toolset + coverage + ROI + genome build + modifiers + sample).

Goal deliverables

Create:

telemetry/consolidated_telemetry.tsv

telemetry/consolidated_telemetry.parquet (optional but preferred)

telemetry/README.md explaining sources, assumptions, and how to regenerate

A reproducible script: scripts/build_telemetry.py (or .ipynb only if unavoidable)

Hard requirements

The output must be deterministic and re-runnable.

It must contain one row per pipeline run unit at the finest grain available (prefer per-sample, per-toolset, per-ROI, per-coverage).

It must include both “raw” telemetry and “derived” cost/vCPU metrics.

It must preserve enough keys to join to concordance + bench tables.

Inputs available (discover in repo)

Search the workspace for:

consolidated_bench.tsv (toolset-level compute summary)

consolidated_concordance.tsv (performance metrics)

any run logs or metadata, e.g.:

Nextflow: trace.txt, .nextflow.log, timeline.html, report.html

Cromwell/WDL: cromwell-executions/*/workflow.logs, metadata.json, call-*/*/execution/stdout|stderr, rc, job.log

Snakemake: .snakemake/log, cluster logs

Slurm: sacct, scontrol show job, slurm-*.out

AWS Batch: CloudWatch logs, job describe JSON, environment, vCPU/memory, start/stop timestamps

Terra/Batch: *.json metadata with runtime & cost fields

Local run manifests: run.json, manifest.yaml, config.yaml, “samplesheet”, etc.

If there’s an S3 bucket with logs referenced in code, find it and support pulling via aws s3 cp --requester-pays (but do NOT assume credentials exist; if missing, create code paths that work with local logs only).

Output schema (TSV columns)

Implement the following columns exactly (snake_case):

Identity / join keys

run_id : stable unique id for the run row (hash of key fields is fine)

workflow_id : workflow-level id if available (Cromwell workflow ID, Nextflow run name, Batch job id, etc)

sample_id : sample identifier (required; if not available, infer from file paths)

genome_build : e.g. hg38, giabHC, etc (align to concordance naming)

roi : region-of-interest label (e.g. clinvar_genes, giabHC, hg38, etc)

variant_class : SNP, Indel_50, INS_50, DEL_50, All, etc (match concordance naming)

primary_platform : e.g. ILMN, ONT, ILMN+ONT (match concordance)

secondary_platform : optional; e.g. ONT for hybrid

toolset : canonical string: (<platform>) <aligner>+<caller> or whatever matches your heatmap rows

aligner : parsed component

caller : parsed component

modifiers : JSON string or semicolon-delimited list of toggles (e.g. SMNCopyNumber;Gauchian); empty allowed

primary_cov_bin : label used in concordance heatmap columns (e.g. 1x, 3x, 5x, 7x, 10x, 30x)

secondary_cov_bin : for hybrid columns (e.g. 7x, 10x) else empty

primary_mean_cov : numeric, if available

secondary_mean_cov : numeric, if available

Raw runtime telemetry

start_time_utc : ISO8601

end_time_utc : ISO8601

wall_time_sec : end-start, numeric

cpu_time_sec : from logs if available (sum across tasks), else null

max_rss_gb : peak resident memory

max_vmem_gb : optional

max_disk_gb : optional

io_read_gb : optional

io_write_gb : optional

Resource allocation telemetry

scheduler : slurm, aws_batch, nextflow_local, cromwell, etc

instance_type : AWS instance type if available

vcpu_allocated : integer

mem_gb_allocated : numeric

storage_gb_allocated : numeric optional

queue : batch queue / slurm partition / etc

Cost telemetry (best effort)

cost_usd_reported : numeric if reported directly in logs/metadata

price_per_vcpu_hour_usd : numeric if you can infer instance pricing (otherwise null)

cost_usd_estimated : numeric estimate if pricing known OR can be derived from a provided rate table

cost_source : enum string: reported|estimated|unknown

cost_notes : free text for caveats

Derived / normalized metrics

vcpu_hours : vcpu_allocated * wall_time_sec / 3600

usd_per_run : choose reported if present else estimated else null

usd_per_vcpu_hour_effective : usd_per_run / vcpu_hours if possible

efficiency_cpu_util : cpu_time_sec / (vcpu_allocated * wall_time_sec) if cpu_time_sec present

pipeline_stage : optional; if you have per-task granularity, also emit stage rows OR keep only workflow-level row. Prefer workflow-level row for now.

Provenance

source_path : path to the log/metadata parsed

parser : name/version of parser module

parse_warnings : semicolon-delimited warnings (missing times, missing sample id, etc)

Implementation instructions

Create a discovery layer that scans likely directories for run artifacts:

Grep for trace.txt, metadata.json, workflowId, AWS_BATCH_JOB_ID, slurmstepd, sacct, etc.

Build a list of candidate runs and their associated files.

Implement parsers (modular):

parse_nextflow_trace(trace.txt) → per-task & workflow aggregates

parse_cromwell_metadata(metadata.json) → call-level metrics aggregated

parse_slurm_logs(slurm*.out) + optional sacct text dumps

parse_aws_batch_describe(job.json) if present

Normalize fields:

Convert all times to UTC ISO8601.

Convert memory units to GB, time to seconds.

Determine join keys:

Map / infer toolset, aligner, caller, platform(s), genome build, ROI, coverage bins from:

run config files, command lines, output directory naming, or run manifests.

Provide a mapping function (dictionary) for known toolset strings to canonical values (this must align with concordance heatmap rows).

If exact variant_class isn’t present in telemetry logs (common), set to All and keep; but prefer per-variant outputs if logs exist.

Join sanity check:

Read consolidated_concordance.tsv and show how many telemetry rows can join on:
(sample_id, roi, genome_build, toolset, primary_cov_bin, secondary_cov_bin, maybe variant_class)

Print a report: join rate, top unmatched reasons, example unmatched keys.

Output:

Write TSV with strict column order as defined.

Write Parquet (optional) with proper types.

Tests / validation:

Assert required columns exist.

Assert wall_time_sec > 0 for rows with times.

Assert vcpu_allocated > 0 when scheduler indicates batch/slurm.

Deduplicate: no duplicate run_id.

Emit summary stats to console:

counts by scheduler, toolset

distribution of wall_time_sec, vcpu_hours

rows with missing key fields

If some required fields are not available

Leave them null and add a parse warning; do not invent values.

Still emit rows; do not drop runs unless completely unusable.

CLI

Make the script runnable as:

python scripts/build_telemetry.py \
  --repo-root . \
  --concordance consolidated_concordance.tsv \
  --bench consolidated_bench.tsv \
  --out_tsv telemetry/consolidated_telemetry.tsv \
  --out_parquet telemetry/consolidated_telemetry.parquet
Extra: optional instance pricing table

If the repo already has a pricing table, use it. Otherwise:

Add a small local telemetry/aws_price_overrides.tsv mechanism:
columns: instance_type, region, usd_per_hour

If missing, skip estimated cost.

Completion criteria

You are done when:

the telemetry TSV is generated successfully,

the join report is produced,

the README documents where telemetry came from and known gaps,

and the output is versionable (no huge binary logs checked in).

Start by scanning the repo to identify which workflow engine produced runs, then implement only the needed parser(s) first, but keep the design modular.