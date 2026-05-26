# `ugrun` MultiQC Contract

The immediate DayOA integration exports MultiQC custom content. The future native MultiQC module consumes the same normalized outputs and must not require DayOA-specific paths.

## Section Contract

| Section ID | Section Name | Parent |
| --- | --- | --- |
| `ultima_run_inventory` | `Ultima Run Inventory` | `dayoa_input_demux_read_qc` |
| `ultima_demux_summary` | `Ultima Demux / Barcode Summary` | `dayoa_input_demux_read_qc` |
| `ultima_trimmer_stats` | `Ultima Trimmer Stats` | `dayoa_input_demux_read_qc` |
| `ultima_trimmer_failures` | `Ultima Trimmer Failure Codes` | `dayoa_input_demux_read_qc` |
| `ultima_flowq_summary` | `Ultima FlowQ Summary` | `dayoa_input_demux_read_qc` |
| `ultima_snvq_summary` | `Ultima SNVQ Summary` | `dayoa_input_demux_read_qc` |
| `ultima_coverage_summary` | `Ultima Coverage Summary` | `dayoa_alignment_coverage` |
| `ultima_picard_summary` | `Ultima Picard / Basic Run Metrics` | `dayoa_alignment_coverage` |
| `ultima_contamination` | `Ultima Contamination / Sample Swap` | `dayoa_variant_benchmark_annotation` |
| `ultima_upload_status` | `Ultima Upload Status` | `dayoa_workflow_reporting` |
| `ultima_unmatched` | `Ultima Unmatched Outputs` | `dayoa_input_demux_read_qc` |

## Sample IDs

| Row class | `Sample` value |
| --- | --- |
| Run-level | `<run_id>` |
| Barcode/sample | `<run_id>.<barcode_id>.<sample_id>` |
| Per-file | `<run_id>.<barcode_id>.<sample_id>.<file_kind>` |
| Unmatched | `<run_id>.unmatched.<file_kind>` |

Safe tokenization:

- Strip whitespace.
- Replace slashes with `_`.
- Allow only `[A-Za-z0-9._+-]`.
- Never emit `Sample` as only `R1`, `R2`, `metrics`, or a bare biological sample when run context matters.

## Custom Data Search Patterns

The DayOA config registers these paths under `results/day/<build>/run_qc/ultima/`:

```yaml
sp:
  ultima_run_inventory:
    fn: "run_qc/ultima/**/ultima_run_inventory_mqc.tsv"
  ultima_demux_summary:
    fn: "run_qc/ultima/**/ultima_demux_summary_mqc.tsv"
```

Each TSV has `Sample` as the first column.

Example:

```tsv
Sample	run_id	barcode_id	sample_id	expected_outputs	observed_outputs	missing_required_outputs
602202.Z0157.KPF011_1	602202	Z0157	KPF011_1	9	9	0
```

