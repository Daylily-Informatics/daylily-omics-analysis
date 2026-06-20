#!/usr/bin/env python3
"""Rewrite BCL Convert fastq_list.csv paths after scratch copy-back."""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path


FASTQ_COLUMNS = {"read1file", "read2file"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fastq-list", required=True)
    parser.add_argument("--from-root", required=True)
    parser.add_argument("--to-root", required=True)
    return parser.parse_args()


def relative_to_or_none(path: Path, root: Path) -> Path | None:
    try:
        return path.relative_to(root)
    except ValueError:
        return None


def resolve_for_check(value: str, fastq_list: Path) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return (fastq_list.parent / path).resolve()


def rewrite_value(value: str, from_root: Path, to_root: Path) -> str:
    text = str(value or "").strip()
    if not text:
        return text
    path = Path(text)
    if not path.is_absolute():
        return text
    relative = relative_to_or_none(path, from_root)
    if relative is None:
        return text
    return str(to_root / relative)


def main() -> int:
    args = parse_args()
    fastq_list = Path(args.fastq_list)
    from_root = Path(args.from_root).resolve()
    to_root = Path(args.to_root).resolve()

    with fastq_list.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise SystemExit(f"ERROR: {fastq_list} has no header row.")
        fieldnames = list(reader.fieldnames)
        rows = [{key: (value or "").strip() for key, value in row.items() if key} for row in reader]

    fastq_fields = [field for field in fieldnames if field.lower() in FASTQ_COLUMNS]
    if not fastq_fields:
        raise SystemExit(f"ERROR: {fastq_list} has no Read1File/Read2File columns.")

    rewrite_count = 0
    for row in rows:
        for field in fastq_fields:
            original = row.get(field, "")
            rewritten = rewrite_value(original, from_root, to_root)
            if rewritten != original:
                rewrite_count += 1
                row[field] = rewritten
            if not row.get(field, ""):
                raise SystemExit(f"ERROR: {fastq_list} row has blank {field}: {row}")
            checked = resolve_for_check(row[field], fastq_list)
            if not checked.exists():
                raise SystemExit(f"ERROR: rewritten BCL Convert FASTQ path does not exist: {checked}")

    tmp_path = fastq_list.with_name(f".{fastq_list.name}.tmp")
    with tmp_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp_path, fastq_list)
    print(
        "rewrote_bclconvert_fastq_list_paths "
        f"fastq_list={fastq_list} from_root={from_root} to_root={to_root} rewrites={rewrite_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
