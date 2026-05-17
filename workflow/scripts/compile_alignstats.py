#!/usr/bin/env python3
"""Compile per-sample alignstats TSVs into MultiQC-ready aggregate TSVs."""

from __future__ import annotations

import argparse
import csv
import glob
import shutil
from pathlib import Path


CORE_FIELDS = ["Sample", "base_sample", "aligner", "deduper"]


def _path_context(path: str) -> dict[str, str]:
    parts = Path(path).parts
    for index, part in enumerate(parts):
        if part == "align" and index >= 1 and index + 2 < len(parts):
            return {
                "base_sample": parts[index - 1],
                "aligner": parts[index + 1],
                "deduper": parts[index + 2],
            }
    return {"base_sample": "", "aligner": "", "deduper": ""}


def _read_rows(path: str) -> list[dict[str, str]]:
    with open(path, encoding="utf-8") as handle:
        lines = [line.rstrip("\n") for line in handle if line.strip()]
    if not lines:
        return []

    header = lines[0]
    if "\t" in header:
        reader = csv.DictReader(lines, delimiter="\t")
        return [dict(row) for row in reader]

    fields = header.split()
    rows: list[dict[str, str]] = []
    for line in lines[1:]:
        values = line.split()
        row = dict(zip(fields, values, strict=False))
        rows.append(row)
    return rows


def _normalise_row(path: str, row: dict[str, str]) -> tuple[list[str], dict[str, str]]:
    context = _path_context(path)
    base_sample = context["base_sample"] or row.get("base_sample", "")
    aligner = context["aligner"] or row.get("aligner", "")
    deduper = context["deduper"] or row.get("deduper", "")
    sample_id = ".".join(part for part in [base_sample, aligner, deduper] if part)

    normalised = {
        "Sample": sample_id or row.get("Sample", "") or row.get("sample", ""),
        "base_sample": base_sample,
        "aligner": aligner,
        "deduper": deduper,
    }
    metric_fields: list[str] = []
    for field, value in row.items():
        if field in {"Sample", "sample", "base_sample", "aligner", "deduper", ""}:
            continue
        if field is None:
            continue
        metric_fields.append(field)
        normalised[field] = value
    return metric_fields, normalised


def collect_rows(mdir: str) -> tuple[list[str], list[dict[str, str]]]:
    mdir_prefix = mdir.rstrip("/") + "/"
    paths = sorted(
        glob.glob(f"{mdir_prefix}*/align/*/*/alignqc/alignstats/*alignstats.tsv")
    )
    rows: list[dict[str, str]] = []
    metric_fieldnames: list[str] = []
    for path in paths:
        for row in _read_rows(path):
            fields, normalised = _normalise_row(path, row)
            for field in fields:
                if field not in metric_fieldnames:
                    metric_fieldnames.append(field)
            rows.append(normalised)

    fieldnames = CORE_FIELDS + metric_fieldnames
    return fieldnames, rows


def write_tsv(path: str, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    out_path = Path(path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mdir", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--bsummary", required=True)
    parser.add_argument("--csummary", required=True)
    parser.add_argument("--combo", required=True)
    parser.add_argument("--generalstats", required=True)
    args = parser.parse_args()

    fieldnames, rows = collect_rows(args.mdir)
    log_path = Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as handle:
        handle.write("STARTcompileAstats\n")
        handle.write(f"rows\t{len(rows)}\n")
        handle.write(f"columns\t{len(fieldnames)}\n")

    write_tsv(args.bsummary, fieldnames, rows)
    write_tsv(args.csummary, fieldnames, rows)
    write_tsv(args.combo, fieldnames, rows)
    shutil.copyfile(args.combo, args.generalstats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
