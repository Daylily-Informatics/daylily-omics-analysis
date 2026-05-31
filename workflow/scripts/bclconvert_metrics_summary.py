#!/usr/bin/env python3
"""Normalize BCL Convert metric CSVs and emit a compact rollup JSON."""

from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Iterable


EXPECTED_HEADERS = {
    "fastq_list.csv": ["RGID", "RGSM", "RGLB", "Lane", "Read1File", "Read2File"],
    "Demultiplex_Stats.csv": [
        "Lane",
        "SampleID",
        "Index",
        "# Reads",
        "# Perfect Index Reads",
        "# One Mismatch Index Reads",
        "# Two Mismatch Index Reads",
        "% Reads",
        "% Perfect Index Reads",
        "% One Index Reads",
        "% Two Index Reads",
        "# of ≥ Q30 Bases (PF)",
        "Mean Quality Score (PF)",
        "QualityScoreSum",
        "ReadNumber",
    ],
    "Top_Unknown_Barcodes.csv": [
        "Lane",
        "index",
        "index2",
        "# Reads",
        "% of Unknown Barcodes",
        "% of All Reads",
    ],
    "Index_Hopping_Counts.csv": [
        "Lane",
        "SampleID",
        "index",
        "index2",
        "# Reads",
        "% of Hopped Reads",
        "% of All Reads",
    ],
}

SPECIAL_HEADER_MAP = {
    "RGID": "rgid",
    "RGSM": "rgsm",
    "RGLB": "rglb",
    "Lane": "lane",
    "Read1File": "read1_file",
    "Read2File": "read2_file",
    "SampleID": "sample_id",
    "Sample_ID": "sample_id",
    "Index": "index",
    "index": "index",
    "index2": "index2",
    "Index2": "index2",
    "# Reads": "reads",
    "# Perfect Index Reads": "perfect_index_reads",
    "# One Mismatch Index Reads": "one_mismatch_index_reads",
    "# Two Mismatch Index Reads": "two_mismatch_index_reads",
    "% Reads": "reads_pct",
    "% Perfect Index Reads": "perfect_index_reads_pct",
    "% One Index Reads": "one_index_reads_pct",
    "% Two Index Reads": "two_index_reads_pct",
    "# of ≥ Q30 Bases (PF)": "q30_bases_pf",
    "Mean Quality Score (PF)": "mean_quality_score_pf",
    "QualityScoreSum": "quality_score_sum",
    "ReadNumber": "read_number",
    "Yield": "yield",
    "YieldQ30": "yield_q30",
    "% Adapter Bases": "pct_adapter_bases",
    "AdapterBases": "adapter_bases",
    "% of Unknown Barcodes": "pct_of_unknown_barcodes",
    "% of Hopped Reads": "pct_of_hopped_reads",
    "% of All Reads": "pct_of_all_reads",
    "RunName": "run_name",
    "InstrumentPlatform": "instrument_platform",
    "SoftwareVersion": "software_version",
    "OverrideCycles": "override_cycles",
    "Sample_Project": "sample_project",
    "Sample_Name": "sample_name",
    "SOURCE_ROW": "source_row",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--report-dir", required=True, nargs="+")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--demux-out", required=True)
    parser.add_argument("--unknown-out", required=True)
    parser.add_argument("--hopping-out", required=True)
    parser.add_argument("--fastq-manifest-out", required=True)
    parser.add_argument("--rollup-json-out", required=True)
    return parser.parse_args()


def normalize_header(name: str) -> str:
    if name in SPECIAL_HEADER_MAP:
        return SPECIAL_HEADER_MAP[name]
    text = unicodedata.normalize("NFKD", str(name))
    text = text.encode("ascii", "ignore").decode("ascii")
    text = text.strip()
    text = text.replace("%", " pct ")
    text = text.replace("#", " num ")
    text = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", text)
    text = re.sub(r"[^A-Za-z0-9]+", "_", text)
    text = re.sub(r"_+", "_", text)
    return text.lower().strip("_")


def first_nonempty(*values: object) -> str:
    for value in values:
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def read_csv_rows(path: Path, required: bool, expected_headers: list[str] | None = None) -> tuple[list[str], list[dict[str, str]]]:
    if not path.exists():
        if required:
            raise SystemExit(f"ERROR: Missing required report file: {path}")
        return (expected_headers or [], [])

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        if not fieldnames:
            if required:
                raise SystemExit(f"ERROR: Required report file has no header row: {path}")
            return (expected_headers or [], [])

        rows: list[dict[str, str]] = []
        for row in reader:
            cleaned = {key: (value or "").strip() for key, value in row.items() if key is not None}
            if any(cleaned.values()):
                rows.append(cleaned)
        if required and not rows:
            raise SystemExit(f"ERROR: Required report file has no data rows: {path}")
        return (fieldnames, rows)


def read_csv_rows_from_dirs(
    report_dirs: list[Path],
    filename: str,
    *,
    required: bool,
    expected_headers: list[str] | None = None,
) -> tuple[list[str], list[dict[str, str]]]:
    merged_fieldnames: list[str] | None = None
    merged_rows: list[dict[str, str]] = []
    for report_dir in report_dirs:
        path = report_dir / filename
        fieldnames, rows = read_csv_rows(path, required=required, expected_headers=expected_headers)
        if not fieldnames:
            continue
        if merged_fieldnames is None:
            merged_fieldnames = fieldnames
        elif fieldnames != merged_fieldnames:
            raise SystemExit(
                "ERROR: report header mismatch for "
                f"{filename}: {path} has {fieldnames}, expected {merged_fieldnames}"
            )
        merged_rows.extend(rows)

    if required and merged_fieldnames is None:
        joined = ", ".join(str(report_dir) for report_dir in report_dirs)
        raise SystemExit(f"ERROR: no readable {filename} found under report dirs: {joined}")
    return (merged_fieldnames or expected_headers or [], merged_rows)


def convert_value(value: str) -> object:
    text = first_nonempty(value)
    if text == "":
        return ""
    text = text.replace(",", "")
    if re.fullmatch(r"-?\d+", text):
        try:
            return int(text)
        except ValueError:
            return text
    if re.fullmatch(r"-?(?:\d+\.\d*|\d*\.\d+)", text):
        try:
            return float(text)
        except ValueError:
            return text
    return text


def normalize_rows(fieldnames: Iterable[str], rows: list[dict[str, str]], run_id: str) -> tuple[list[str], list[dict[str, str]]]:
    normalized_headers = [normalize_header(name) for name in fieldnames]
    output_rows: list[dict[str, str]] = []
    for row in rows:
        normalized_row = {"run_id": run_id}
        for raw_name, norm_name in zip(fieldnames, normalized_headers):
            normalized_row[norm_name] = first_nonempty(row.get(raw_name))
        output_rows.append(normalized_row)
    return (["run_id", *normalized_headers], output_rows)


def write_tsv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def lane_key(row: dict[str, str]) -> str:
    return first_nonempty(row.get("lane"), row.get("Lane"))


def sample_key(row: dict[str, str]) -> str:
    return first_nonempty(row.get("sample_id"), row.get("SampleID"), row.get("sampleid"))


def add_list_bucket(bucket: dict[str, list[dict[str, object]]], lane: str, row: dict[str, object]) -> None:
    bucket.setdefault(lane, []).append(row)


def infer_run_id(path: Path) -> str:
    try:
        bclconvert_index = path.parts.index("bclconvert")
    except ValueError:
        bclconvert_index = -1
    if bclconvert_index > 0 and path.parts[bclconvert_index - 1] != "results":
        return path.parts[bclconvert_index - 1]
    try:
        return path.parents[1].name
    except IndexError:
        return path.stem


def main() -> int:
    args = parse_args()
    report_dirs = [Path(report_dir) for report_dir in args.report_dir]
    run_id = args.run_id.strip() or infer_run_id(report_dirs[0])

    demux_fieldnames, demux_rows = read_csv_rows_from_dirs(
        report_dirs,
        "Demultiplex_Stats.csv",
        required=True,
        expected_headers=EXPECTED_HEADERS["Demultiplex_Stats.csv"],
    )
    fastq_fieldnames, fastq_rows = read_csv_rows_from_dirs(
        report_dirs,
        "fastq_list.csv",
        required=True,
        expected_headers=EXPECTED_HEADERS["fastq_list.csv"],
    )
    unknown_fieldnames, unknown_rows = read_csv_rows_from_dirs(
        report_dirs,
        "Top_Unknown_Barcodes.csv",
        required=False,
        expected_headers=EXPECTED_HEADERS["Top_Unknown_Barcodes.csv"],
    )
    hopping_fieldnames, hopping_rows = read_csv_rows_from_dirs(
        report_dirs,
        "Index_Hopping_Counts.csv",
        required=False,
        expected_headers=EXPECTED_HEADERS["Index_Hopping_Counts.csv"],
    )

    demux_headers, demux_norm = normalize_rows(demux_fieldnames, demux_rows, run_id)
    fastq_headers, fastq_norm = normalize_rows(fastq_fieldnames, fastq_rows, run_id)
    unknown_headers, unknown_norm = normalize_rows(unknown_fieldnames, unknown_rows, run_id)
    hopping_headers, hopping_norm = normalize_rows(hopping_fieldnames, hopping_rows, run_id)

    write_tsv(Path(args.demux_out), demux_headers, demux_norm)
    write_tsv(Path(args.fastq_manifest_out), fastq_headers, fastq_norm)
    write_tsv(Path(args.unknown_out), unknown_headers, unknown_norm)
    write_tsv(Path(args.hopping_out), hopping_headers, hopping_norm)

    total_pf_reads_by_lane: dict[str, int] = defaultdict(int)
    reads_by_sample_by_lane: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    perfect_index_reads_by_lane: dict[str, int] = defaultdict(int)
    one_mismatch_index_reads_by_lane: dict[str, int] = defaultdict(int)
    undetermined_reads_by_lane: dict[str, int] = defaultdict(int)

    for row in demux_norm:
        lane = lane_key(row)
        sample_id = sample_key(row)
        reads = int(convert_value(row.get("reads", "")) or 0)
        perfect_reads = int(convert_value(row.get("perfect_index_reads", "")) or 0)
        one_mismatch = int(convert_value(row.get("one_mismatch_index_reads", "")) or 0)

        total_pf_reads_by_lane[lane] += reads
        reads_by_sample_by_lane[lane][sample_id] += reads
        perfect_index_reads_by_lane[lane] += perfect_reads
        one_mismatch_index_reads_by_lane[lane] += one_mismatch
        if sample_id.lower() == "undetermined":
            undetermined_reads_by_lane[lane] += reads

    top_unknown_barcodes_by_lane: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in unknown_norm:
        lane = lane_key(row)
        entry = {
            "index": first_nonempty(row.get("index")),
            "index2": first_nonempty(row.get("index2")),
            "reads": convert_value(row.get("reads", "")),
        }
        if row.get("sample_id"):
            entry["sample_id"] = row.get("sample_id")
        add_list_bucket(top_unknown_barcodes_by_lane, lane, entry)

    index_hopping_counts_by_lane: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in hopping_norm:
        lane = lane_key(row)
        entry = {
            "sample_id": first_nonempty(row.get("sample_id")),
            "index": first_nonempty(row.get("index")),
            "index2": first_nonempty(row.get("index2")),
            "reads": convert_value(row.get("reads", "")),
            "pct_of_hopped_reads": convert_value(row.get("pct_of_hopped_reads", "")),
            "pct_of_all_reads": convert_value(row.get("pct_of_all_reads", "")),
        }
        add_list_bucket(index_hopping_counts_by_lane, lane, entry)

    rollup = {
        "run_id": run_id,
        "report_dirs": [str(report_dir) for report_dir in report_dirs],
        "demultiplex_stats": {
            "total_pf_reads_by_lane": dict(sorted(total_pf_reads_by_lane.items())),
            "reads_by_sample_by_lane": {
                lane: dict(sorted(sample_map.items()))
                for lane, sample_map in sorted(reads_by_sample_by_lane.items())
            },
            "perfect_index_reads_by_lane": dict(sorted(perfect_index_reads_by_lane.items())),
            "one_mismatch_index_reads_by_lane": dict(sorted(one_mismatch_index_reads_by_lane.items())),
            "undetermined_reads_by_lane": dict(sorted(undetermined_reads_by_lane.items())),
        },
        "top_unknown_barcodes_by_lane": {
            lane: rows for lane, rows in sorted(top_unknown_barcodes_by_lane.items())
        },
        "index_hopping_counts_by_lane": {
            lane: rows for lane, rows in sorted(index_hopping_counts_by_lane.items())
        },
    }

    rollup_path = Path(args.rollup_json_out)
    rollup_path.parent.mkdir(parents=True, exist_ok=True)
    with rollup_path.open("w", encoding="utf-8", newline="") as handle:
        json.dump(rollup, handle, indent=2, sort_keys=True)
        handle.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
