#!/usr/bin/env python3
"""Convert Truvari summary JSON into MultiQC-style TSV outputs."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Iterable


FIELDNAMES = [
    "Sample",
    "InputSample",
    "base_sample",
    "Aligner",
    "Deduper",
    "SVCaller",
    "AltId",
    "ROI",
    "TP-base",
    "TP-comp",
    "FP",
    "FN",
    "Precision",
    "Sensitivity-Recall",
    "Fscore",
    "BaseCount",
    "CompCount",
    "BaseSizeFiltered",
    "CompSizeFiltered",
    "BaseGtFiltered",
    "CompGtFiltered",
    "TP-comp_TP-gt",
    "TP-comp_FP-gt",
    "TP-base_TP-gt",
    "TP-base_FP-gt",
    "GtPrecision",
    "GtRecall",
    "GtFscore",
    "GtConcordance",
    "TruthVCF",
    "QueryVCF",
]


SUMMARY_KEY_MAP = {
    "TP-base": ("TP-base",),
    "TP-comp": ("TP-comp", "TP-call"),
    "FP": ("FP",),
    "FN": ("FN",),
    "Precision": ("precision",),
    "Sensitivity-Recall": ("recall",),
    "Fscore": ("f1",),
    "BaseCount": ("base cnt",),
    "CompCount": ("comp cnt", "call cnt"),
    "BaseSizeFiltered": ("base size filtered",),
    "CompSizeFiltered": ("comp size filtered", "call size filtered"),
    "BaseGtFiltered": ("base gt filtered",),
    "CompGtFiltered": ("comp gt filtered", "call gt filtered"),
    "TP-comp_TP-gt": ("TP-comp_TP-gt", "TP-call_TP-gt"),
    "TP-comp_FP-gt": ("TP-comp_FP-gt", "TP-call_FP-gt"),
    "TP-base_TP-gt": ("TP-base_TP-gt",),
    "TP-base_FP-gt": ("TP-base_FP-gt",),
    "GtPrecision": ("gt_precision",),
    "GtRecall": ("gt_recall",),
    "GtFscore": ("gt_f1",),
    "GtConcordance": ("gt_concordance",),
}


def _first_value(data: dict[str, Any], keys: Iterable[str]) -> Any:
    for key in keys:
        if key in data:
            return data[key]
    return ""


def _format_value(value: Any) -> str:
    if value is None:
        return ""
    return str(value)


def load_summary(path: str | Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Truvari summary must be a JSON object: {path}")
    return data


def summary_to_row(
    summary: dict[str, Any],
    *,
    sample: str,
    stage_sample: str,
    roi: str,
    alt_id: str,
    aligner: str,
    deduper: str,
    sv_caller: str,
    truth_vcf: str,
    query_vcf: str,
) -> dict[str, str]:
    row: dict[str, str] = {
        "Sample": f"{stage_sample}.{roi}",
        "InputSample": sample,
        "base_sample": sample,
        "Aligner": aligner,
        "Deduper": deduper,
        "SVCaller": sv_caller,
        "AltId": alt_id,
        "ROI": roi,
        "TruthVCF": truth_vcf,
        "QueryVCF": query_vcf,
    }
    for output_key, summary_keys in SUMMARY_KEY_MAP.items():
        row[output_key] = _format_value(_first_value(summary, summary_keys))
    return {field: row.get(field, "") for field in FIELDNAMES}


def write_one(args: argparse.Namespace) -> None:
    summary = load_summary(args.summary)
    row = summary_to_row(
        summary,
        sample=args.sample,
        stage_sample=args.stage_sample,
        roi=args.roi,
        alt_id=args.alt_id,
        aligner=args.aligner,
        deduper=args.deduper,
        sv_caller=args.sv_caller,
        truth_vcf=args.truth_vcf,
        query_vcf=args.query_vcf,
    )
    write_rows([row], args.output)


def read_rows(path: str | Path) -> tuple[list[str], list[dict[str, str]]]:
    with Path(path).open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames is None:
            return FIELDNAMES, []
        return list(reader.fieldnames), list(reader)


def write_rows(rows: list[dict[str, str]], output: str | Path) -> None:
    out_path = Path(output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in FIELDNAMES})


def aggregate(args: argparse.Namespace) -> None:
    rows: list[dict[str, str]] = []
    for path in args.inputs:
        fieldnames, path_rows = read_rows(path)
        if fieldnames != FIELDNAMES:
            raise ValueError(f"Truvari MQC header mismatch in {path}: {fieldnames}")
        rows.extend(path_rows)
    rows.sort(key=lambda row: (row.get("Sample", ""), row.get("ROI", "")))
    write_rows(rows, args.output)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    one = subparsers.add_parser("one", help="write one MQC TSV from one summary JSON")
    one.add_argument("--summary", required=True)
    one.add_argument("--output", required=True)
    one.add_argument("--sample", required=True)
    one.add_argument("--stage-sample", required=True)
    one.add_argument("--roi", required=True)
    one.add_argument("--alt-id", required=True)
    one.add_argument("--aligner", required=True)
    one.add_argument("--deduper", required=True)
    one.add_argument("--sv-caller", required=True)
    one.add_argument("--truth-vcf", required=True)
    one.add_argument("--query-vcf", required=True)
    one.set_defaults(func=write_one)

    aggregate_parser = subparsers.add_parser(
        "aggregate", help="concatenate per-ROI Truvari MQC TSVs"
    )
    aggregate_parser.add_argument("--output", required=True)
    aggregate_parser.add_argument("inputs", nargs="*")
    aggregate_parser.set_defaults(func=aggregate)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
