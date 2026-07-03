#!/usr/bin/env python3
"""Summarize a manifest-driven SMNCopyNumberCaller contract run."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


FIELDNAMES = [
    "sample",
    "caller",
    "input_class",
    "input_path",
    "reference_path",
    "resource_dir",
    "genome",
    "expected_smn1",
    "expected_smn2",
    "observed_smn1",
    "observed_smn2",
    "observed_smn2delta78",
    "carrier",
    "affected",
    "total_cn_raw",
    "full_length_cn_raw",
    "preflight_production_eligible",
    "preflight_input_scope",
    "preflight_failed_requirements",
    "expected_match_status",
    "parse_status",
    "source_analysis",
    "summary_json",
]


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _walk_values(value: Any, key: str) -> list[Any]:
    found: list[Any] = []
    if isinstance(value, dict):
        for current_key, current_value in value.items():
            if str(current_key).lower() == key.lower():
                found.append(current_value)
            found.extend(_walk_values(current_value, key))
    elif isinstance(value, list):
        for item in value:
            found.extend(_walk_values(item, key))
    return found


def _first_key(data: Any, *keys: str) -> str:
    for key in keys:
        values = _walk_values(data, key)
        for value in values:
            if value is not None and str(value) != "":
                return str(value)
    return "not_reported"


def _first_row(path: Path) -> dict[str, str]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not rows:
        raise SystemExit(f"TSV has no data rows: {path}")
    return rows[0]


def _failed_requirements(path: Path) -> str:
    failed: list[str] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if row.get("status") != "PASS":
                failed.append(row.get("requirement", "unknown"))
    return ",".join(failed) if failed else "none"


def _match_status(expected_smn1: str, expected_smn2: str, observed_smn1: str, observed_smn2: str) -> str:
    if observed_smn1 in {"not_reported", "None", "none", ""} or observed_smn2 in {"not_reported", "None", "none", ""}:
        return "NO_EXACT_CN"
    if observed_smn1 == expected_smn1 and observed_smn2 == expected_smn2:
        return "MATCH"
    return "DISCORDANT"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--resource-dir", required=True)
    parser.add_argument("--genome", required=True)
    parser.add_argument("--expected-smn1", required=True)
    parser.add_argument("--expected-smn2", required=True)
    parser.add_argument("--source-analysis", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--input-qc", required=True)
    parser.add_argument("--required-status", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    summary_path = Path(args.summary_json)
    data = _load_json(summary_path)
    qc_row = _first_row(Path(args.input_qc))

    observed_smn1 = _first_key(data, "SMN1_CN", "smn1_cn", "smn1_copy_number", "SMN1_copy_number")
    observed_smn2 = _first_key(data, "SMN2_CN", "smn2_cn", "smn2_copy_number", "SMN2_copy_number")
    observed_delta = _first_key(data, "SMN2delta78", "smn2delta78", "smn_del78_cn", "SMN2_del78_CN")
    parse_status = (
        "PARSED_EXACT_CN"
        if observed_smn1 != "not_reported" and observed_smn2 != "not_reported"
        else "PARSE_INCOMPLETE"
    )

    row = {
        "sample": args.sample,
        "caller": "SMNCopyNumberCaller",
        "input_class": "whole_genome_wgs_bam_cram",
        "input_path": args.input,
        "reference_path": args.reference,
        "resource_dir": args.resource_dir,
        "genome": args.genome,
        "expected_smn1": args.expected_smn1,
        "expected_smn2": args.expected_smn2,
        "observed_smn1": observed_smn1,
        "observed_smn2": observed_smn2,
        "observed_smn2delta78": observed_delta,
        "carrier": _first_key(data, "isCarrier", "carrier", "is_carrier"),
        "affected": _first_key(data, "isSMA", "affected", "is_affected"),
        "total_cn_raw": _first_key(data, "total_cn_raw", "total_raw_cn", "total_cn"),
        "full_length_cn_raw": _first_key(data, "full_length_cn_raw", "full_length_raw_cn", "full_cn_raw"),
        "preflight_production_eligible": qc_row.get("production_eligible", "not_reported"),
        "preflight_input_scope": qc_row.get("input_scope", "not_reported"),
        "preflight_failed_requirements": _failed_requirements(Path(args.required_status)),
        "expected_match_status": _match_status(args.expected_smn1, args.expected_smn2, observed_smn1, observed_smn2),
        "parse_status": parse_status,
        "source_analysis": args.source_analysis,
        "summary_json": str(summary_path),
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerow(row)
    if parse_status != "PARSED_EXACT_CN":
        raise SystemExit(
            "SMNCopyNumberCaller contract summary did not expose exact SMN1 and SMN2 CN fields; "
            f"see {summary_path}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
