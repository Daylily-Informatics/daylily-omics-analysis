#!/usr/bin/env python3
"""Compile goleft indexcov PED summaries into MultiQC custom content."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


OUTPUT_FIELDS = [
    "Sample",
    "base_sample",
    "aligner",
    "deduper",
    "family_id",
    "reported_sample_id",
    "sex",
    "phenotype",
    "CNchrX",
    "CNchrY",
    "bins_out",
    "bins_lo",
    "bins_hi",
    "bins_in",
    "slope",
    "p_out",
    "ped_path",
]


def parse_stage_parts(path: Path) -> tuple[str, str, str]:
    parts = path.resolve().parts
    try:
        align_idx = parts.index("align")
    except ValueError as exc:
        raise ValueError(f"could not parse goleft path: {path}") from exc
    if align_idx < 1 or align_idx + 2 >= len(parts):
        raise ValueError(f"incomplete goleft path: {path}")
    return parts[align_idx - 1], parts[align_idx + 1], parts[align_idx + 2]


def normalized_reader(path: Path) -> csv.DictReader:
    handle = path.open(newline="", encoding="utf-8")
    reader = csv.DictReader(handle, delimiter="\t")
    if not reader.fieldnames:
        handle.close()
        raise ValueError(f"goleft PED has no header: {path}")
    reader.fieldnames = [
        "family_id" if field == "#family_id" else field for field in reader.fieldnames
    ]
    return reader


def compile_rows(paths: list[Path]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in paths:
        base_sample, aligner, deduper = parse_stage_parts(path)
        stage_sample = f"{base_sample}.{aligner}.{deduper}"
        reader = normalized_reader(path)
        with reader:
            for row in reader:
                rows.append(
                    {
                        "Sample": stage_sample,
                        "base_sample": base_sample,
                        "aligner": aligner,
                        "deduper": deduper,
                        "family_id": row.get("family_id", ""),
                        "reported_sample_id": row.get("sample_id", ""),
                        "sex": row.get("sex", ""),
                        "phenotype": row.get("phenotype", ""),
                        "CNchrX": row.get("CNchrX", ""),
                        "CNchrY": row.get("CNchrY", ""),
                        "bins_out": row.get("bins.out", ""),
                        "bins_lo": row.get("bins.lo", ""),
                        "bins_hi": row.get("bins.hi", ""),
                        "bins_in": row.get("bins.in", ""),
                        "slope": row.get("slope", ""),
                        "p_out": row.get("p.out", ""),
                        "ped_path": str(path),
                    }
                )
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("ped", nargs="+")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = compile_rows([Path(path) for path in args.ped])
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_FIELDS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
