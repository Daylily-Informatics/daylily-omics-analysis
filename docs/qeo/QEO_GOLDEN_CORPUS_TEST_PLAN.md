# QEO Golden Corpus Test Plan

**Golden corpus goal:** prove that DayOA registration and QEO ingest manifests are deterministic, parser-ready, and replay-safe before live Dewey/QEO ingestion.

## Corpus

Use the GIAB MultiQC corpus already used by QEO planning and parser tests. The corpus should contain:

- final MultiQC HTML,
- `DAY_final_multiqc_data/`,
- `multiqc_data.json`,
- `multiqc_general_stats.txt`,
- `multiqc_sources.txt`,
- `multiqc.log`,
- representative custom `_mqc.tsv` files,
- staged `manifest.tsv`,
- expected QEO parser fixture outputs where available.

## Test Matrix

| Scenario | Expected result |
|---|---|
| Deterministic inventory | Same input tree produces byte-identical canonical JSON across reruns when `generated_at` is fixed. |
| Deterministic hashes | SHA256 for every file equals direct file hash. |
| Parser file classification | HTML, data JSON, general stats, sources, log, stage manifest, and `_mqc.tsv` files are parser-relevant. |
| Required file enforcement | Missing required MultiQC files fail loudly. |
| Unknown file preservation | Unknown files remain in the artifact manifest and are excluded from parser hints. |
| Sample-name collision warnings | Duplicate staged sample identity warnings are preserved without turning into QC decisions. |
| Rerun idempotency | Manifest checksum and Dewey idempotency key remain stable for identical content. |
| Local-only mode | Local receipt uses `local_only` status and does not fabricate Dewey EUIDs. |
| Replay-safe behavior | Outbox event ID is deterministic from event type, payload, and correlation ID. |
| No PHI in events | Event payload contains EUIDs, checksums, counts, and artifact refs only. |

## Current Local Tests

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
python -m pytest -q tests/test_qeo_registration.py
```

The local tests build a small synthetic MultiQC fixture and cover deterministic manifests, parser classification, missing required files, unknown preservation, sample collision warnings, local-only receipts, idempotency keys, and replay-safe events.

## Future GIAB Corpus Expansion

Add a fixture directory or archive under `.test_data/data/qeo/giab_multiqc/` with a manifest that records:

- source corpus name,
- expected file count,
- expected parser-relevant file count,
- expected manifest checksum,
- expected parser hints,
- expected warning count,
- expected QEO parser metric count.

Do not embed live cluster assumptions in golden tests. Live cluster checks belong in execution ledgers and should be marked blocked until a working `daylily-ec`/SSM headnode is available.

