#!/usr/bin/env python3
"""Write Illumina InterOp summary CSVs using the Python interop API."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Iterable

import interop


def _value(value: object) -> object:
    if hasattr(value, "item"):
        return value.item()
    return value


def _write_structured_array(path: Path, rows: object, fallback_header: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    names = getattr(getattr(rows, "dtype", None), "names", None)
    header = list(names or fallback_header)
    if not header:
        raise SystemExit(f"Cannot infer InterOp columns for {path}")

    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        if names is None:
            return
        for row in rows:
            writer.writerow([_value(row[name]) for name in header])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-folder", required=True)
    parser.add_argument("--summary-out", required=True)
    parser.add_argument("--index-summary-out", required=True)
    parser.add_argument("--summary-level", default="Lane")
    parser.add_argument("--index-level", default="Barcode")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_folder = Path(args.run_folder)
    if not run_folder.is_dir():
        raise SystemExit(f"run folder does not exist: {run_folder}")

    summary_rows = interop.summary(str(run_folder), level=args.summary_level)
    index_rows = interop.index_summary(str(run_folder), level=args.index_level)

    summary_header = interop.summary_columns(level=args.summary_level)
    index_header = interop.index_summary_columns(level=args.index_level)
    if args.summary_level in {"Lane", "Surface"}:
        summary_header = ("ReadNumber", "IsIndex", args.summary_level, *summary_header)
    if args.index_level == "Lane":
        index_header = ("Lane", *index_header)
    elif args.index_level == "Barcode":
        index_header = ("Lane", *index_header)

    _write_structured_array(Path(args.summary_out), summary_rows, summary_header)
    _write_structured_array(Path(args.index_summary_out), index_rows, index_header)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
