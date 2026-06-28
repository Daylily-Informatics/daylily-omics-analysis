#!/usr/bin/env python3
"""Inventory existing files considered by the generic DayOA MultiQC scan."""

from __future__ import annotations

import argparse
import csv
import fnmatch
import re
from pathlib import Path


MANIFEST_FIELDS = [
    "rel_path",
    "source_path",
    "size_bytes",
    "kind",
    "configured_patterns",
]

TEXTISH_SUFFIXES = {
    ".csv",
    ".err",
    ".html",
    ".json",
    ".log",
    ".md",
    ".out",
    ".tsv",
    ".txt",
    ".xml",
    ".yaml",
    ".yml",
}

BINARY_OR_BULK_SUFFIXES = {
    ".bam",
    ".bai",
    ".bcf",
    ".bgz",
    ".crai",
    ".cram",
    ".fq",
    ".gz",
    ".jpeg",
    ".jpg",
    ".npy",
    ".npz",
    ".pdf",
    ".png",
    ".simg",
    ".tbi",
    ".zip",
}

EXCLUDED_PARTS = {
    ".git",
    ".snakemake",
    "__pycache__",
    "multiqc_inputs",
}

CONFIG_FN_RE = re.compile(r"^\s*fn:\s*[\"']?([^\"'#]+)[\"']?\s*(?:#.*)?$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--config", action="append", default=[], type=Path)
    parser.add_argument("--max-size-mb", default=256, type=int)
    return parser.parse_args()


def configured_patterns(config_paths: list[Path]) -> list[str]:
    patterns: list[str] = []
    for config_path in config_paths:
        if not config_path.is_file():
            continue
        for line in config_path.read_text(encoding="utf-8").splitlines():
            match = CONFIG_FN_RE.match(line)
            if not match:
                continue
            value = match.group(1).strip()
            if value:
                patterns.append(value)
    return sorted(set(patterns))


def excluded(path: Path) -> bool:
    parts = set(path.parts)
    if parts & EXCLUDED_PARTS:
        return True
    return any(part.endswith("_multiqc_data") for part in path.parts)


def is_textish_candidate(path: Path, max_size_bytes: int) -> bool:
    if excluded(path) or not path.is_file():
        return False
    if path.name.startswith("."):
        return False
    if path.name.endswith(".pyc"):
        return False
    if "multiqc" in path.name:
        return False
    if path.suffix in BINARY_OR_BULK_SUFFIXES:
        return False
    if path.stat().st_size > max_size_bytes:
        return False
    if path.suffix in TEXTISH_SUFFIXES:
        return True
    return path.name.endswith((".metrics", ".stats", ".report"))


def matching_configured_patterns(rel_path: str, patterns: list[str]) -> list[str]:
    return [pattern for pattern in patterns if fnmatch.fnmatch(rel_path, pattern)]


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    max_size_bytes = args.max_size_mb * 1024 * 1024
    patterns = configured_patterns(args.config)

    rows: dict[str, dict[str, str]] = {}
    for path in sorted(root.rglob("*")):
        if excluded(path) or not path.is_file():
            continue
        rel_path = path.relative_to(root).as_posix()
        configured = matching_configured_patterns(rel_path, patterns)
        textish = is_textish_candidate(path, max_size_bytes)
        if not configured and not textish:
            continue
        kinds = []
        if textish:
            kinds.append("textish_existing_output")
        if configured:
            kinds.append("configured_multiqc_source")
        rows[rel_path] = {
            "rel_path": rel_path,
            "source_path": str(path),
            "size_bytes": str(path.stat().st_size),
            "kind": ",".join(kinds),
            "configured_patterns": ";".join(configured),
        }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_FIELDS, delimiter="\t")
        writer.writeheader()
        for row in sorted(rows.values(), key=lambda item: item["rel_path"]):
            writer.writerow(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
