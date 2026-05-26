# Ultima RunQC MultiQC CloudFront Publish Ledger

Created: 2026-05-26T12:47:49Z

## Objective

Publish the generated all-Ultima-run MultiQC report through the existing authenticated DayOA CloudFront report surface, using AWS profile `lsmc`, without broadening bucket-policy or CloudFront distribution scope unless explicitly approved.

## Gate 0: Read-Only Baseline

- Local report HTML: `/Users/jmajor/Downloads/ULTIMA_RUNQC/ultima_all_runs.multiqc.html`, 3.1M.
- Local report data dir: `/Users/jmajor/Downloads/ULTIMA_RUNQC/ultima_all_runs.multiqc_data`, 1.1M.
- Local data JSON: `/Users/jmajor/Downloads/ULTIMA_RUNQC/ultima_all_runs.multiqc_data/multiqc_data.json`, 792K.
- Local discovered-runs manifest: `/Users/jmajor/Downloads/ULTIMA_RUNQC/discovered_runs.tsv`.
- Local source manifest: `/Users/jmajor/Downloads/ULTIMA_RUNQC/source_manifest.tsv`, 10M.
- Source Ultima run dirs: 10 prefixes under `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN*/2026/`.
- AWS profile/account verified read-only: `lsmc`, account `108782052779`.
- Existing CloudFront distribution: `E1O1EGAADAALSL`, domain `dlqovrcm5y71h.cloudfront.net`.
- Existing CloudFront origin for root S3 paths: `s3-run-qc-illumina-all-root-20260518`, bucket `lsmc-dayoa-omics-analysis-us-west-2`, empty origin path.
- Existing authenticated cache behavior already covers `analysis_results/ubuntu/html_reports/*` and uses Basic Auth function `arn:aws:cloudfront::108782052779:function/lsmc-giab-20x30x-v2-basic-auth-20260511`.
- Existing bucket-policy grant already covers `arn:aws:s3:::lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/html_reports/*` for CloudFront distribution `E1O1EGAADAALSL`.
- Proposed target prefix is currently empty: `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/html_reports/ultima_runqc_all/`.

## Proposed Exact Effect

After explicit approval, upload these local artifacts:

- `/Users/jmajor/Downloads/ULTIMA_RUNQC/ultima_all_runs.multiqc.html`
- `/Users/jmajor/Downloads/ULTIMA_RUNQC/ultima_all_runs.multiqc_data/**`

to:

- `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/html_reports/ultima_runqc_all/`

Expected authenticated URL:

- `https://dlqovrcm5y71h.cloudfront.net/analysis_results/ubuntu/html_reports/ultima_runqc_all/ultima_all_runs.multiqc.html`

Expected data URL:

- `https://dlqovrcm5y71h.cloudfront.net/analysis_results/ubuntu/html_reports/ultima_runqc_all/ultima_all_runs.multiqc_data/multiqc_data.json`

This path uses the already-registered `html_reports/*` CloudFront behavior and existing bucket-policy grant. It does not require CloudFront distribution mutation or S3 bucket-policy mutation. No S3 objects existed under the proposed target prefix at Gate 0, so the upload is expected to create new objects rather than overwrite existing report objects.

## Approval Gate

Do not perform the upload, invalidate CloudFront, or emit a final share URL until the user gives explicit approval after seeing the proposed effect.

Suggested approval phrase:

`APPROVE PUBLISH ULTIMA_RUNQC_HTML_REPORTS`

## Rows

| ID | Area | Requirement | Status | Evidence | Terminal Note |
|---|---|---|---|---|---|
| INV-001 | Baseline | Record local artifacts, source runs, CloudFront distribution, target origin, cache behavior, and bucket-policy coverage. | DONE | Read-only AWS checks saved `docs/plans/20260526T123000Z_ultima_runqc_example/cloudfront_E1O1EGAADAALSL_config.json` and `docs/plans/20260526T123000Z_ultima_runqc_example/lsmc-dayoa-bucket-policy.json`. | Existing `html_reports/*` route can serve the report without policy/distribution mutation. |
| APPROVAL-001 | Approval | Get explicit approval for S3 upload/share issuance. | DONE | User replied `APPROVE PUBLISH ULTIMA_RUNQC_HTML_REPORTS` in chat. | Approval received 2026-05-26. |
| PUBLISH-001 | S3 | Upload HTML and `multiqc_data` dir to target prefix. | DONE | Uploaded 19 objects to `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/html_reports/ultima_runqc_all/`. | No CloudFront distribution or bucket-policy mutation performed. |
| VERIFY-001 | CloudFront | Verify S3 byte count and authenticated CloudFront gate. | DONE | Local: 19 files, 4,318,657 bytes. S3: 19 objects, 4,318,657 bytes. HTML head-object `ContentLength=3250643`, `ContentType=text/html`, `CacheControl=no-cache`. Unauthenticated CloudFront `HEAD` returned `401` with `www-authenticate: Basic realm="LSMC QC"`. | Authenticated `200` was not tested because credentials were not needed or requested for this publish. |

## Publish Result

Published at: 2026-05-26T12:54:11Z

- S3 prefix: `s3://lsmc-dayoa-omics-analysis-us-west-2/analysis_results/ubuntu/html_reports/ultima_runqc_all/`
- CloudFront report URL: `https://dlqovrcm5y71h.cloudfront.net/analysis_results/ubuntu/html_reports/ultima_runqc_all/ultima_all_runs.multiqc.html`
- CloudFront data JSON URL: `https://dlqovrcm5y71h.cloudfront.net/analysis_results/ubuntu/html_reports/ultima_runqc_all/ultima_all_runs.multiqc_data/multiqc_data.json`
- Invalidation: not run. These were new keys under the authenticated `html_reports/*` behavior.
