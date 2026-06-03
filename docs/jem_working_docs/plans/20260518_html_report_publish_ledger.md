# 20260518 HTML Report Publish Ledger

Date: 2026-05-18
Owner: orchestrator
Repository: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
Request: update the sequencing analysis state report with run-state labels and publish an authenticated HTML version at `analysis_results/ubuntu/html_reports/20260518.html`.

## Gate 0: Inventory Freeze

Status: SUCCESS

Baseline captured:

- Repo branch: `codex/multiqc-qc-no-dedup-default`
- AWS profile confirmed by user earlier in this thread: `lsmc`
- AWS account from `AWS_PROFILE=lsmc aws sts get-caller-identity`: `108782052779`
- Markdown report: `docs/202260518_sequening_analysis_state.md`
- HTML output: `docs/20260518.html`
- S3 target: `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/html_reports/20260518.html`
- CloudFront distribution: `E1O1EGAADAALSL`, domain `dlqovrcm5y71h.cloudfront.net`
- Existing root-origin target for non-FSx paths: `s3-run-qc-illumina-all-root-20260518`
- Basic Auth username: `lsmc-qc-curious`
- Basic Auth password: supplied in chat, not recorded here

Assumptions and limits:

- Run-state precedence used in the report: `Exception` overrides everything; MultiQC present means `QC complete`; alignstats present means `Aligned`; otherwise source-ready runs are `demuxed`.
- Illumina `0008` was set to `<in progress>` by explicit user request.
- No success-only URL checks were added back to the markdown report.

## Publish Evidence

- Rendered `docs/20260518.html` from the markdown report: `23,130` bytes.
- Uploaded HTML object with `ContentType=text/html` and `CacheControl=no-cache`.
- Added bucket-policy Sid: `AllowCloudFrontReadHtmlReports20260518`
- Added cache behavior: `analysis_results/ubuntu/html_reports/*`, target origin `s3-run-qc-illumina-all-root-20260518`
- Distribution `E1O1EGAADAALSL` returned to `Deployed`.
- Invalidation: `I2AU4QJOWAOAP4EC1TC1299STA`, path `/analysis_results/ubuntu/html_reports/20260518.html`, status `Completed`
- Unauthenticated CloudFront probe returned `401`.
- Authenticated CloudFront probe returned `200` and `23,130` bytes.

Restyle evidence:

- Updated `docs/20260518.html` embedded CSS to dark neon report styling while preserving report content.
- Re-uploaded the HTML object to the same S3 key: `24,797` bytes, `ContentType=text/html`, `CacheControl=no-cache`.
- Invalidation: `I43CGWHRBCDT9V88ZO6L35WQ55`, path `/analysis_results/ubuntu/html_reports/20260518.html`, status `Completed`.
- Unauthenticated CloudFront probe returned `401`.
- Authenticated CloudFront probe returned `200` and `24,797` bytes.

## Tracking Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GOAL-001 | Objective | Publish the report as authenticated CloudFront HTML. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Authenticated probe returned `200`; unauthenticated probe returned `401`. |  | Objective complete. |
| DOC-001 | Markdown | Add run-state labels and platform run-state counts. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `docs/202260518_sequening_analysis_state.md` includes `Run State Summary` and 18 `Run Name` state labels. |  | Markdown report updated. |
| DOC-002 | Markdown | Set Illumina `0008` to `<in progress>`. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `20260514_23andMe_run-2` heading and `Run Name` line show `<in progress>`. |  | Explicit user state applied. |
| HTML-001 | HTML | Render a standalone HTML version of the report. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `docs/20260518.html`, `23,130` bytes. |  | HTML artifact generated. |
| S3-001 | S3 | Upload the HTML report to the requested S3 key. | SUCCESS | feature_implementation | Gate 3 | orchestrator | `aws s3 ls` showed `analysis_results/ubuntu/html_reports/20260518.html`, `23,130` bytes. |  | S3 object present with HTML content type. |
| CF-001 | CloudFront | Route `analysis_results/ubuntu/html_reports/*` through the authenticated root-origin behavior. | SUCCESS | feature_implementation | Gate 3 | orchestrator | Added cache behavior on `E1O1EGAADAALSL`; distribution deployed. |  | CloudFront route active. |
| CF-002 | CloudFront | Keep unauthenticated access gated while allowing authenticated report access. | SUCCESS | contract_test | Gate 5 | orchestrator | `curl` returned unauthenticated `401` and authenticated `200`. |  | Auth behavior verified. |
| STYLE-001 | HTML | Restyle the report as a dark neon business-appropriate report. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `docs/20260518.html` contains `color-scheme: dark`; live authenticated probe returned `24,797` bytes after invalidation `I43CGWHRBCDT9V88ZO6L35WQ55`. |  | Restyled HTML is published at the same CloudFront URL. |
