#!/usr/bin/env python3
"""Summarize exploratory Paraphase-on-ONT output."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


FIELDNAMES = [
    "sample",
    "caller",
    "exploratory_label",
    "input_class",
    "input_path",
    "reference_path",
    "expected_smn1",
    "expected_smn2",
    "observed_smn1",
    "observed_smn2",
    "observed_smn_del78",
    "smn1_read_number",
    "smn2_read_number",
    "smn_del78_read_number",
    "expected_match_status",
    "parse_status",
    "json_path",
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


def _match_status(expected_smn1: str, expected_smn2: str, observed_smn1: str, observed_smn2: str) -> str:
    if observed_smn1 in {"not_reported", "None", "none", ""} or observed_smn2 in {"not_reported", "None", "none", ""}:
        return "NO_EXACT_CN"
    if observed_smn1 == expected_smn1 and observed_smn2 == expected_smn2:
        return "MATCH_EXPLORATORY"
    return "DISCORDANT_EXPLORATORY"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--expected-smn1", required=True)
    parser.add_argument("--expected-smn2", required=True)
    parser.add_argument("--exploratory-label", required=True)
    parser.add_argument("--input-class", required=True)
    parser.add_argument("--json-path", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if args.exploratory_label != "EXPLORATORY_ONT_PARAPHASE":
        raise SystemExit(
            "Paraphase ONT outputs must be labeled EXPLORATORY_ONT_PARAPHASE."
        )

    json_path = Path(args.json_path)
    data = _load_json(json_path)
    observed_smn1 = _first_key(data, "smn1_cn", "SMN1_CN", "smn1_copy_number")
    observed_smn2 = _first_key(data, "smn2_cn", "SMN2_CN", "smn2_copy_number")
    observed_delta = _first_key(data, "smn2_del78_cn", "smn_del78_cn", "SMN2delta78")
    parse_status = (
        "PARSED_EXACT_CN_EXPLORATORY"
        if observed_smn1 != "not_reported" and observed_smn2 != "not_reported"
        else "PARSE_INCOMPLETE_EXPLORATORY"
    )
    row = {
        "sample": args.sample,
        "caller": "Paraphase",
        "exploratory_label": args.exploratory_label,
        "input_class": args.input_class,
        "input_path": args.input,
        "reference_path": args.reference,
        "expected_smn1": args.expected_smn1,
        "expected_smn2": args.expected_smn2,
        "observed_smn1": observed_smn1,
        "observed_smn2": observed_smn2,
        "observed_smn_del78": observed_delta,
        "smn1_read_number": _first_key(data, "smn1_read_number"),
        "smn2_read_number": _first_key(data, "smn2_read_number"),
        "smn_del78_read_number": _first_key(data, "smn_del78_read_number", "smn2_del78_read_number"),
        "expected_match_status": _match_status(args.expected_smn1, args.expected_smn2, observed_smn1, observed_smn2),
        "parse_status": parse_status,
        "json_path": str(json_path),
    }
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerow(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
