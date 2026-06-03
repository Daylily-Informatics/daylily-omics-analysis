# run_qc_ont_all CloudFront Publish Ledger

Date: 2026-05-18
Owner: orchestrator
Repository: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
Request: expose the MultiQC report for `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/run_qc_ont_all/` through the existing authenticated CloudFront report URL pattern.

## Gate 0: Inventory Freeze

Status: SUCCESS

Baseline captured:

- Repo branch: `codex/multiqc-qc-no-dedup-default`
- Repo HEAD: `6f0082c47c2a1fac1d4d51d70857461ae3c67238`
- Git status: `M workflow/rules/common.smk`
- Pre-existing dirty file not owned by this publish task: `workflow/rules/common.smk`
- AWS CLI available after `conda activate DAY-EC`: `aws-cli/1.44.69`
- AWS profile confirmed by user: `lsmc`
- AWS account from `AWS_PROFILE=lsmc aws sts get-caller-identity`: `108782052779`
- Target source prefix: `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/run_qc_ont_all/`
- Prior publish lead from memory, to be re-verified live before use: CloudFront distribution `E2XJKZDRX9JT1I`, domain `d2d7oi0nffmsro.cloudfront.net`, Basic Auth realm `LSMC QC`
- User supplied Basic Auth username for verification: `lsmc-qc-curious`
- User supplied Basic Auth password: provided in chat, not repeated in this ledger

Assumptions and limits:

- The live publish step is not complete from memory alone; current S3 keys, CloudFront origin config, and bucket policy must be inspected with an explicit non-default AWS profile.
- The existing CloudFront pattern should be reused if live state still matches prior evidence; do not introduce a new auth scheme.
- Do not perform S3 bucket-policy mutation, CloudFront distribution mutation, or CloudFront invalidation until the exact effect is stated and separately approved in this thread.
- Do not rely on inferred AWS defaults or service-side discovery as a substitute for the required profile.

Read-only live evidence:

- Source report candidate 1: `analysis_results/ubuntu/run_qc_ont_all/ont_runs.multiqc.html`, `2,293,311` bytes, last modified `2026-05-18T09:05:17Z`
- Source data tree candidate 1: `analysis_results/ubuntu/run_qc_ont_all/ont_runs.multiqc_data/multiqc_data.json`, `663,486` bytes, last modified `2026-05-18T09:05:19Z`
- Source report candidate 2: `analysis_results/ubuntu/run_qc_ont_all/ont_demux_fastq.multiqc.html`, `3,537,459` bytes, last modified `2026-05-18T13:40:53Z`
- Source data tree candidate 2: `analysis_results/ubuntu/run_qc_ont_all/ont_demux_fastq.multiqc_data/multiqc_data.json`, `2,361,537` bytes, last modified `2026-05-18T13:41:01Z`
- Distribution `E2XJKZDRX9JT1I` is deployed at `d2d7oi0nffmsro.cloudfront.net` but currently points to `/FSxLustre20260515T103052Z/analysis_results/ubuntu/multiqc_kitchen_hg002_hg003_10x_20260517/daylily-omics-analysis/results/day/hg38/reports`.
- Distribution `E1O1EGAADAALSL` is deployed at `dlqovrcm5y71h.cloudfront.net`, has the same Basic Auth function, and already has cache behaviors for `analysis_results/ubuntu/run_qc_illumina_all/*` and `analysis_results/jem-scratch/run_qc_illumina_all/*` targeting root-origin id `s3-run-qc-illumina-all-root-20260518`.
- The bucket policy already grants `E1O1EGAADAALSL` CloudFront read access to both `run_qc_illumina_all` prefixes, but not to `analysis_results/ubuntu/run_qc_ont_all/*`.
- Authenticated probe of `https://dlqovrcm5y71h.cloudfront.net/analysis_results/ubuntu/run_qc_ont_all/ont_demux_fastq.multiqc.html` returned `403 AccessDenied`; unauthenticated probe returned `401`.

Publish evidence:

- User approval: `APPROVE PUBLISH run_qc_ont_all`
- Added bucket-policy Sid: `AllowCloudFrontReadRunQcOntAll20260518`
- Updated distribution: `E1O1EGAADAALSL`, status moved from `InProgress` to `Deployed`, last modified `2026-05-18T13:56:51.784Z`
- Added cache behavior: `analysis_results/ubuntu/run_qc_ont_all/*`, target origin `s3-run-qc-illumina-all-root-20260518`, existing Basic Auth function `arn:aws:cloudfront::108782052779:function/lsmc-giab-20x30x-v2-basic-auth-20260511`
- Invalidation: `IC3DFVFJCJWIA2R8IRHKBPTOKH`, path `/analysis_results/ubuntu/run_qc_ont_all/*`, status `Completed`
- Unauthenticated probes returned `401` for both report URLs.
- Authenticated probes returned `200`:
  - `ont_demux_fastq.multiqc.html`, `3,537,459` bytes
  - `ont_demux_fastq.multiqc_data/multiqc_data.json`, `2,361,537` bytes
  - `ont_runs.multiqc.html`, `2,293,311` bytes
  - `ont_runs.multiqc_data/multiqc_data.json`, `663,486` bytes

## Tracking Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GOAL-001 | Objective | Expose the requested `run_qc_ont_all` MultiQC report through an authenticated CloudFront URL. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Authenticated CloudFront probes returned `200` for both report URLs and their `multiqc_data.json` files. |  | Objective complete. |
| INV-001 | Baseline | Record repo, dirty state, AWS CLI availability, prior publish lead, and source prefix before live work. | SUCCESS | legitimate_safety_handling | Gate 0 | orchestrator | `git status --short --branch`; `git rev-parse HEAD`; `aws --version`; memory-backed prior CloudFront lead. |  | Baseline recorded; pre-existing dirty file identified and left untouched. |
| AWS-001 | Credentials | Use an explicit non-default AWS profile for all AWS reads and writes. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | User specified `lsmc`; `aws sts get-caller-identity` returned account `108782052779`. |  | All AWS commands use `AWS_PROFILE=lsmc`; no default profile used. |
| SRC-001 | S3 Source | Verify the current S3 source contains the MultiQC HTML and full data tree or the correct current report/data names. | SUCCESS | legitimate_safety_handling | Gate 1 | orchestrator | `ont_runs.multiqc.html`, `ont_runs.multiqc_data/multiqc_data.json`, `ont_demux_fastq.multiqc.html`, and `ont_demux_fastq.multiqc_data/multiqc_data.json` all exist under the target prefix. |  | Source prefix has both run-level and demux/FASTQ MultiQC reports; the demux/FASTQ report is newer. |
| CF-001 | CloudFront | Verify the current CloudFront distribution domain, origin path, auth function, and bucket-policy read grant for the exact report prefix. | SUCCESS | legitimate_safety_handling | Gate 1 | orchestrator | `E1O1EGAADAALSL` is deployed at `dlqovrcm5y71h.cloudfront.net`, uses the existing Basic Auth function, has root-origin cache behaviors for `run_qc_illumina_all`, and lacks a grant for `run_qc_ont_all`; authenticated ONT probe returned `403 AccessDenied`. |  | Reuse `E1O1EGAADAALSL`; add a sibling behavior and exact bucket-policy grant for `analysis_results/ubuntu/run_qc_ont_all/*`. |
| PUB-001 | Publish | Prepare and apply the exact S3/CloudFront change needed to expose the target report without broadening unrelated access. | SUCCESS | feature_implementation | Gate 3 | orchestrator | Added cache behavior `analysis_results/ubuntu/run_qc_ont_all/*`, bucket-policy Sid `AllowCloudFrontReadRunQcOntAll20260518`, and invalidation `IC3DFVFJCJWIA2R8IRHKBPTOKH`. |  | Scoped publish change applied and deployed. |
| APPROVAL-001 | Live Approval | Before any CloudFront/share issuance, S3 bucket-policy mutation, distribution update, or invalidation, restate the exact effect and obtain separate explicit approval. | SUCCESS | active_product_contract | Gate 3 | orchestrator | User approved with `APPROVE PUBLISH run_qc_ont_all` after the exact effect was stated. |  | Approval gate satisfied before live mutation. |
| VERIFY-001 | Verification | Verify authenticated URL returns `200` for the report HTML and at least one data-tree object, and unauthenticated access remains gated. | SUCCESS | contract_test | Gate 5 | orchestrator | Unauthenticated probes returned `401`; authenticated probes returned `200` for both HTML reports and both `multiqc_data.json` objects. |  | Authenticated CloudFront exposure works and unauthenticated access remains gated. |
