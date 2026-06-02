# DayOA S3 Bucket Delete Ledger

Created: 2026-06-02T07:38:34Z

## Objective

Delete exactly four approved S3 buckets and their contents, with no archive, backup, lifecycle wait, copy, fallback target, or alternate discovery path.

## Approval

The user first requested a delete plan, reviewed the destructive plan, then sent: "PLEASE IMPLEMENT THIS PLAN:" followed by the full approved plan. This ledger treats that as the second explicit destructive approval required by workspace policy.

## Gate 0: Inventory Freeze

Ledger path: `/Users/jmajor/projects/daylily/daylily-omics-analysis/docs/plans/20260602T073834Z_dayoa_s3_bucket_delete_ledger.md`

Repo path: `/Users/jmajor/projects/daylily/daylily-omics-analysis`

Initial repo status:

```text
## codex/dayoa-bclconvert-tile-shards-20260601...origin/codex/dayoa-bclconvert-tile-shards-20260601
 M AGENTS.md
```

The modified `AGENTS.md` is pre-existing and unrelated; this execution will not edit it.

Approved target matrix:

| ID | Profile | Expected Account | Bucket | Region | Status | Category | Approval Gate | Evidence | Root Cause | Terminal Note |
|---|---|---:|---|---|---|---|---|---|---|---|
| DEL-001 | `lsmc` | `108782052779` | `lsmc-dayoa-omics-analysis-eu-central-1` | `eu-central-1` | `SUCCESS` | destructive_aws_bucket_delete | Gate 0-5 | Preflight: 107,138 objects, 1,893,118,823,593 bytes, versioning disabled, no Object Lock, no replication, 4 multipart uploads. Deleted 107,138 objects in 108 batches, aborted 4 multipart uploads. `head-bucket` returned 404 and `list-buckets` absent. |  | Bucket and contents deleted; independent post-run verification returned 404/absent. |
| DEL-002 | `lsmc` | `108782052779` | `lsmc-dayoa-omics-analysis-ap-south-1` | `ap-south-1` | `SUCCESS` | destructive_aws_bucket_delete | Gate 0-5 | Preflight: 82,786 objects, 708,462,740,176 bytes, versioning disabled, no Object Lock, no replication, 2 multipart uploads. Deleted 82,786 objects in 83 batches, aborted 2 multipart uploads. `head-bucket` returned 404 and `list-buckets` absent. |  | Bucket and contents deleted; independent post-run verification returned 404/absent. |
| DEL-003 | `daylily` | `670484050738` | `daylily-dayoa-references-usw2` | `us-west-2` | `SUCCESS` | destructive_aws_bucket_delete | Gate 0-5 | Preflight: 6 objects, 70,581 bytes, versioning disabled, no Object Lock, no replication, 0 multipart uploads. Deleted 6 objects in 1 batch. `head-bucket` returned 404 and `list-buckets` absent. |  | Bucket and contents deleted; independent post-run verification returned 404/absent. |
| DEL-004 | `daylily` | `670484050738` | `daylily-service-omics-analysis-us-west-2` | `us-west-2` | `SUCCESS` | destructive_aws_bucket_delete | Gate 0-5 | Preflight: 191,332 objects, 3,910,426,061,467 bytes, versioning disabled, no Object Lock, no replication, 0 multipart uploads. Deleted 191,332 objects in 192 batches. `head-bucket` returned 404 and `list-buckets` absent. |  | Bucket and contents deleted; independent post-run verification returned 404/absent. |

Stop conditions:

- Stop if any profile resolves to the wrong account.
- Stop if any bucket resolves to a different region than approved.
- Stop if any bucket has versioning enabled, MFA Delete enabled, Object Lock configured, or replication configured.
- Stop if any AWS operation would touch a bucket outside the exact four approved names.
- Stop on `AccessDenied` or explicit deny that prevents object deletion or bucket deletion.

## Execution Log

| Time UTC | Step | Result |
|---|---|---|
| 2026-06-02T07:38:34Z | Ledger created. | `OPEN` rows initialized for the four exact buckets. |
| 2026-06-02T07:45:00Z | Helper restart. | First helper run stopped during read-only `DEL-001` counting before any deletion because AWS CLI auto-pagination waited for the whole bucket; helper was patched to force `--no-paginate` for one-page listing. |
| 2026-06-02T08:18:00Z | Destructive execution complete. | Helper log: `/tmp/dayoa_s3_bucket_delete_20260602T073834Z.log`. Final summary reports all four buckets deleted and absent from `list-buckets`. |
| 2026-06-02T08:19:07Z | Independent post-run verification. | Fresh `head-bucket` calls returned 404 for all four exact bucket names; fresh `list-buckets` checks returned `False` for all four exact bucket names. No delete helper or AWS delete subprocess remained running. |

## Final Status

All rows are terminal `SUCCESS`.

No rows are `OPEN`, `IN_PROGRESS`, `ATTEMPTING_BUGFIX`, `FAIL`, or `BLOCKED`.
