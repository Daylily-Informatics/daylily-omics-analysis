#!/usr/bin/env python3
"""Convert normalized BCL Convert metrics into MultiQC custom-data TSVs."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demux-tsv", required=True)
    parser.add_argument("--unknown-tsv", required=True)
    parser.add_argument("--hopping-tsv", required=True)
    parser.add_argument("--fastq-manifest-tsv", required=True)
    parser.add_argument("--rollup-json", required=True)
    parser.add_argument("--demux-out", required=True)
    parser.add_argument("--unknown-out", required=True)
    parser.add_argument("--hopping-out", required=True)
    parser.add_argument("--fastq-manifest-out", required=True)
    parser.add_argument("--lane-summary-out", required=True)
    return parser.parse_args()


def clean_token(value: object, default: str = "NA") -> str:
    text = str(value if value is not None else "").strip()
    if text == "":
        text = default
    text = re.sub(r"\s+", "_", text)
    text = re.sub(r"[^A-Za-z0-9._+-]+", "_", text)
    return text.strip("._") or default


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fieldnames = reader.fieldnames or []
        rows = [{key: (value or "").strip() for key, value in row.items()} for row in reader]
    return fieldnames, rows


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def filtered_fields(*groups: list[str], source_fields: list[str]) -> list[str]:
    fields = ["Sample"]
    for group in groups:
        for field in group:
            if field in source_fields and field not in fields:
                fields.append(field)
    return fields


def demux_rows(path: Path) -> tuple[list[str], list[dict[str, object]]]:
    source_fields, rows = read_tsv(path)
    fields = filtered_fields(
        ["run_id", "lane", "sample_id", "read_number", "index"],
        [
            "reads",
            "reads_pct",
            "perfect_index_reads",
            "perfect_index_reads_pct",
            "one_mismatch_index_reads",
            "one_index_reads_pct",
            "two_mismatch_index_reads",
            "two_index_reads_pct",
            "q30_bases_pf",
            "mean_quality_score_pf",
            "quality_score_sum",
        ],
        source_fields=source_fields,
    )
    out_rows: list[dict[str, object]] = []
    for row in rows:
        sample = ".".join(
            [
                clean_token(row.get("run_id")),
                f"L{clean_token(row.get('lane'))}",
                clean_token(row.get("sample_id")),
                f"R{clean_token(row.get('read_number'))}",
            ]
        )
        out_rows.append({"Sample": sample, **{field: row.get(field, "") for field in fields if field != "Sample"}})
    return fields, out_rows


def fastq_manifest_rows(path: Path) -> tuple[list[str], list[dict[str, object]]]:
    source_fields, rows = read_tsv(path)
    fields = filtered_fields(
        ["run_id", "lane", "rgid", "rgsm", "rglb", "read1_file", "read2_file"],
        source_fields=source_fields,
    )
    out_rows: list[dict[str, object]] = []
    for row in rows:
        sample = ".".join(
            [
                clean_token(row.get("run_id")),
                f"L{clean_token(row.get('lane'))}",
                clean_token(row.get("rgsm")),
                clean_token(row.get("rgid")),
            ]
        )
        out_rows.append({"Sample": sample, **{field: row.get(field, "") for field in fields if field != "Sample"}})
    return fields, out_rows


def unknown_rows(path: Path) -> tuple[list[str], list[dict[str, object]]]:
    source_fields, rows = read_tsv(path)
    fields = filtered_fields(
        ["run_id", "lane", "index", "index2", "reads", "pct_of_unknown_barcodes", "pct_of_all_reads"],
        source_fields=source_fields,
    )
    out_rows: list[dict[str, object]] = []
    for row in rows:
        sample = ".".join(
            [
                clean_token(row.get("run_id")),
                f"L{clean_token(row.get('lane'))}",
                "unknown_barcode",
                clean_token(row.get("index")),
                clean_token(row.get("index2")),
            ]
        )
        out_rows.append({"Sample": sample, **{field: row.get(field, "") for field in fields if field != "Sample"}})
    return fields, out_rows


def hopping_rows(path: Path) -> tuple[list[str], list[dict[str, object]]]:
    source_fields, rows = read_tsv(path)
    fields = filtered_fields(
        ["run_id", "lane", "sample_id", "index", "index2", "reads", "pct_of_hopped_reads", "pct_of_all_reads"],
        source_fields=source_fields,
    )
    out_rows: list[dict[str, object]] = []
    for row in rows:
        sample = ".".join(
            [
                clean_token(row.get("run_id")),
                f"L{clean_token(row.get('lane'))}",
                clean_token(row.get("sample_id")),
                "index_hop",
                clean_token(row.get("index")),
                clean_token(row.get("index2")),
            ]
        )
        out_rows.append({"Sample": sample, **{field: row.get(field, "") for field in fields if field != "Sample"}})
    return fields, out_rows


def lane_summary_rows(path: Path) -> tuple[list[str], list[dict[str, object]]]:
    with path.open("r", encoding="utf-8") as handle:
        rollup = json.load(handle)
    run_id = clean_token(rollup.get("run_id"))
    demux = rollup.get("demultiplex_stats", {})
    total_reads = demux.get("total_pf_reads_by_lane", {})
    perfect_reads = demux.get("perfect_index_reads_by_lane", {})
    one_mismatch_reads = demux.get("one_mismatch_index_reads_by_lane", {})
    undetermined_reads = demux.get("undetermined_reads_by_lane", {})
    top_unknown = rollup.get("top_unknown_barcodes_by_lane", {})
    hopping = rollup.get("index_hopping_counts_by_lane", {})

    fields = [
        "Sample",
        "run_id",
        "lane",
        "total_pf_reads",
        "perfect_index_reads",
        "one_mismatch_index_reads",
        "undetermined_reads",
        "top_unknown_barcode_rows",
        "index_hopping_rows",
    ]
    lanes = sorted(
        set(total_reads)
        | set(perfect_reads)
        | set(one_mismatch_reads)
        | set(undetermined_reads)
        | set(top_unknown)
        | set(hopping),
        key=lambda value: (str(value).zfill(8), str(value)),
    )
    rows = []
    for lane in lanes:
        lane_token = clean_token(lane)
        rows.append(
            {
                "Sample": f"{run_id}.L{lane_token}",
                "run_id": run_id,
                "lane": lane,
                "total_pf_reads": total_reads.get(lane, 0),
                "perfect_index_reads": perfect_reads.get(lane, 0),
                "one_mismatch_index_reads": one_mismatch_reads.get(lane, 0),
                "undetermined_reads": undetermined_reads.get(lane, 0),
                "top_unknown_barcode_rows": len(top_unknown.get(lane, [])),
                "index_hopping_rows": len(hopping.get(lane, [])),
            }
        )
    return fields, rows


def main() -> int:
    args = parse_args()

    for fields, rows, output in (
        (*demux_rows(Path(args.demux_tsv)), Path(args.demux_out)),
        (*unknown_rows(Path(args.unknown_tsv)), Path(args.unknown_out)),
        (*hopping_rows(Path(args.hopping_tsv)), Path(args.hopping_out)),
        (*fastq_manifest_rows(Path(args.fastq_manifest_tsv)), Path(args.fastq_manifest_out)),
        (*lane_summary_rows(Path(args.rollup_json)), Path(args.lane_summary_out)),
    ):
        write_tsv(output, fields, rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
