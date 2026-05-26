#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def read_manifest(path: Path) -> dict[str, int]:
    entries: dict[str, int] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                relpath, size_s = line.split("\t", 1)
            except ValueError as exc:
                raise SystemExit(f"{path}:{line_number}: malformed manifest row") from exc
            entries[relpath] = int(size_s)
    return entries


def write_rows(path: Path, rows: list[tuple[str, int | str, int | str]]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write("\t".join(str(value) for value in row) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fsx", required=True, type=Path)
    parser.add_argument("--s3", required=True, type=Path)
    parser.add_argument("--outdir", required=True, type=Path)
    parser.add_argument("--zero-dir-markers", required=True, type=int)
    args = parser.parse_args()

    args.outdir.mkdir(parents=True, exist_ok=True)
    fsx = read_manifest(args.fsx)
    s3 = read_manifest(args.s3)

    fsx_keys = set(fsx)
    s3_keys = set(s3)
    missing = sorted((key, fsx[key], "") for key in fsx_keys - s3_keys)
    extra = sorted((key, "", s3[key]) for key in s3_keys - fsx_keys)
    mismatches = sorted(
        (key, fsx[key], s3[key])
        for key in fsx_keys & s3_keys
        if fsx[key] != s3[key]
    )

    write_rows(args.outdir / "manifest_missing_in_s3.tsv", missing)
    write_rows(args.outdir / "manifest_extra_in_s3.tsv", extra)
    write_rows(args.outdir / "manifest_size_mismatches.tsv", mismatches)

    fsx_bytes = sum(fsx.values())
    s3_bytes = sum(s3.values())
    summary = [
        f"fsx_files_or_symlinks={len(fsx)}",
        f"s3_file_objects={len(s3)}",
        f"fsx_bytes={fsx_bytes}",
        f"s3_bytes={s3_bytes}",
        f"missing_in_s3={len(missing)}",
        f"extra_in_s3={len(extra)}",
        f"size_mismatches={len(mismatches)}",
        f"zero_byte_s3_directory_markers_ignored={args.zero_dir_markers}",
    ]
    (args.outdir / "manifest_compare_summary.txt").write_text(
        "\n".join(summary) + "\n",
        encoding="utf-8",
    )

    print("\n".join(summary))
    return 0 if not missing and not extra and not mismatches and fsx_bytes == s3_bytes else 1


if __name__ == "__main__":
    raise SystemExit(main())
