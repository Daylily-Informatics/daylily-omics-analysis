# ugrun Metrics Schema

Ultima `ugrun` metrics are emitted as evidence tables. Each table keeps raw run, barcode, sample, file-kind, and metric values so QEO can preserve source-row provenance.

Required columns vary by table, but every parser-backed `_mqc.tsv` must include:

- `Sample`
- run or source identifier columns,
- raw metric columns,
- enough source context to link back to the registered artifact.

The schema does not contain QC pass/fail release authority. R2 owns interpretation.

