# `ugrun` Normalized Metrics Schema

Schema version: `urqc.normalized.v0.1`

Every TSV is UTF-8, tab-delimited, and has a header row. Empty optional values are blank. Required values must be present or the command fails before emitting a successful output.

## Shared Columns

| Column | Type | Required | Unit | Description |
| --- | --- | --- | --- | --- |
| `schema_version` | string | yes |  | `urqc.normalized.v0.1` |
| `run_id` | string | yes |  | Ultima run identifier |
| `sample_id` | string | context |  | Biological/sample-sheet sample ID |
| `barcode_id` | string | context |  | Barcode label such as `Z0157` |
| `barcode_sequence` | string | context |  | Barcode sequence when known |
| `application` | enum | yes |  | Application profile |
| `source_path` | string | context |  | Original source path or URI |
| `parser` | string | yes |  | Parser command that produced the row |
| `warnings` | string | no |  | Semicolon-delimited warning codes |

## Inventory Rows

| Column | Type | Unit |
| --- | --- | --- |
| `file_kind` | string |  |
| `exists` | boolean |  |
| `size_bytes` | integer | bytes |
| `mtime` | string | ISO-8601 |
| `checksum_sha256` | string |  |
| `required` | boolean |  |
| `missing_reason` | string |  |

## Quality Summary Rows

| Column | Type | Unit |
| --- | --- | --- |
| `quality_kind` | enum: `flowq`, `snvq` |  |
| `total_observations` | integer | observations |
| `mean_quality` | float | native score |
| `median_quality` | float | native score |
| `p10_quality` | float | native score |
| `p50_quality` | float | native score |
| `p90_quality` | float | native score |
| `low_quality_fraction` | float | fraction |
| `high_quality_fraction` | float | fraction |
| `threshold_low` | float | native score |
| `threshold_high` | float | native score |

## Coverage Summary Rows

| Column | Type | Unit |
| --- | --- | --- |
| `mean_depth` | float | X |
| `median_depth` | float | X |
| `pct_ge_1x` | float | percent |
| `pct_ge_5x` | float | percent |
| `pct_ge_10x` | float | percent |
| `pct_ge_20x` | float | percent |
| `pct_ge_30x` | float | percent |
| `pct_ge_50x` | float | percent |
| `mapq0_bases` | integer | bases |
| `mapq0_intervals` | integer | intervals |
| `mapq1_bases` | integer | bases |
| `mapq1_intervals` | integer | intervals |
| `callable_fraction` | float | fraction |

## JSON Schema Skeleton

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/lsmc-bio/ur-qc/schemas/urqc.normalized.v0.1.json",
  "type": "object",
  "required": ["schema_version", "run_id", "application", "outputs"],
  "properties": {
    "schema_version": {"const": "urqc.normalized.v0.1"},
    "run_id": {"type": "string", "minLength": 1},
    "application": {"type": "string"},
    "outputs": {"type": "object"},
    "warnings": {"type": "array", "items": {"type": "string"}},
    "errors": {"type": "array", "items": {"type": "string"}}
  },
  "additionalProperties": true
}
```

## Versioning Policy

- Additive optional columns do not change the schema version.
- Removing or renaming a column requires a new minor schema version.
- Changing units or interpretation requires a new minor schema version and an explicit migration note.
- Parser outputs must record their schema version in both TSV and JSON.

