# ugrun MultiQC Contract

Ultima run QC custom-content rows use stable MultiQC sample identifiers.

Expected sample identifier forms:

- `<run_id>.<barcode_id>.<sample_id>`
- `<run_id>.unmatched.<file_kind>`

Allowed characters:

- `[A-Za-z0-9._+-]`

Do not collapse an Ultima sample name into biological identity. The parser must keep raw run, barcode, sample, and file-kind fields available for QEO evidence lineage.

