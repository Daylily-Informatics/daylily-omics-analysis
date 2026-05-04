#!/usr/bin/env python3
"""Summarize selected HTD caller outputs for MultiQC custom content."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path


HTD_RE = re.compile(
    r"(?P<sample>[^/]+)/align/(?P<aligner>[^/]+)/(?P<deduper>[^/]+)/htd/(?P<caller>[^/]+)/"
)

GENES = {
    "gauchian": "GBA",
    "cyrius": "CYP2D6",
    "smn12": "SMN1/SMN2",
    "parascopy": "MULTI",
    "smaca": "SMN1/SMN2",
    "genetocn": "MULTI",
}


def _read_cyrius_tsv(path: Path) -> tuple[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return "NA", "missing_tsv"
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        row = next(reader, None)
    if not row:
        return "NA", "empty_tsv"
    return row.get("Genotype", "NA") or "NA", row.get("Filter", "NA") or "NA"


def _json_path(paths: list[Path]) -> str:
    for path in paths:
        if path.name.endswith(".json"):
            return str(path)
    return "NA"


def _tsv_path(paths: list[Path]) -> str:
    for path in paths:
        if path.name.endswith(".tsv"):
            return str(path)
    return "NA"


def _done_path(paths: list[Path]) -> str:
    for path in paths:
        if path.name.endswith(".done"):
            return str(path)
    return "NA"


def _status(caller: str, paths: list[Path], genotype_filter: str) -> str:
    if caller == "cyrius":
        return genotype_filter
    done = _done_path(paths)
    if done != "NA" and Path(done).exists():
        return "complete"
    if any(path.exists() for path in paths):
        return "partial"
    return "missing"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    groups: dict[tuple[str, str, str, str], list[Path]] = defaultdict(list)
    for raw_path in args.paths:
        match = HTD_RE.search(raw_path)
        if not match:
            continue
        groups[
            (
                match.group("sample"),
                match.group("aligner"),
                match.group("deduper"),
                match.group("caller"),
            )
        ].append(Path(raw_path))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "sample",
        "aligner",
        "deduper",
        "caller",
        "gene",
        "genotype",
        "filter",
        "status",
        "json_path",
        "tsv_path",
        "done_path",
        "output_paths",
    ]

    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for sample, aligner, deduper, caller in sorted(groups):
            paths = sorted(groups[(sample, aligner, deduper, caller)])
            genotype = "NA"
            genotype_filter = "NA"
            if caller == "cyrius":
                genotype, genotype_filter = _read_cyrius_tsv(Path(_tsv_path(paths)))
            writer.writerow(
                {
                    "sample": sample,
                    "aligner": aligner,
                    "deduper": deduper,
                    "caller": caller,
                    "gene": GENES.get(caller, "NA"),
                    "genotype": genotype,
                    "filter": genotype_filter,
                    "status": _status(caller, paths, genotype_filter),
                    "json_path": _json_path(paths),
                    "tsv_path": _tsv_path(paths),
                    "done_path": _done_path(paths),
                    "output_paths": json.dumps([str(path) for path in paths]),
                }
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
