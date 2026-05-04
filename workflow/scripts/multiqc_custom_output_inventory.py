#!/usr/bin/env python3
"""Write a MultiQC custom-data TSV inventory for QC tool outputs."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


SEQQC_RE = re.compile(r"(?P<sample>[^/]+)/seqqc/(?P<tool>[^/]+)/")
ALIGNQC_RE = re.compile(
    r"(?P<sample>[^/]+)/align/(?P<aligner>[^/]+)/(?P<deduper>[^/]+)/alignqc/(?P<tool>[^/]+)"
)

TOOL_ALIASES = {
    "samtmetrics": "samtools_metrics",
    "qmap": "qualimap",
    "norm_cov_eveness": "coverage_evenness",
}


def _output_type(path: Path) -> str:
    name = path.name
    if name.endswith(".done"):
        return "done"
    if name.endswith(".complete"):
        return "complete"
    if name.endswith(".json"):
        return "json"
    if name.endswith(".html"):
        return "html"
    if name.endswith(".tsv"):
        return "tsv"
    if name.endswith(".txt"):
        return "txt"
    if name.endswith(".bed"):
        return "bed"
    if name.endswith(".log"):
        return "log"
    return path.suffix.removeprefix(".") or "file"


def _infer_record(stage: str, path_text: str) -> dict[str, str | int]:
    path = Path(path_text)
    sample = "NA"
    tool = "unknown"
    aligner = "NA"
    deduper = "NA"

    align_match = ALIGNQC_RE.search(path_text)
    seq_match = SEQQC_RE.search(path_text)
    if align_match:
        groups = align_match.groupdict()
        sample = groups["sample"]
        tool = TOOL_ALIASES.get(groups["tool"], groups["tool"])
        aligner = groups["aligner"]
        deduper = groups["deduper"]
    elif seq_match:
        groups = seq_match.groupdict()
        sample = groups["sample"]
        tool = TOOL_ALIASES.get(groups["tool"], groups["tool"])

    try:
        stat = path.stat()
        exists = "yes"
        size_bytes = stat.st_size
    except OSError:
        exists = "no"
        size_bytes = 0

    return {
        "sample": sample,
        "stage": stage,
        "tool": tool,
        "aligner": aligner,
        "deduper": deduper,
        "output_type": _output_type(path),
        "exists": exists,
        "size_bytes": size_bytes,
        "source_path": path_text,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "sample",
        "stage",
        "tool",
        "aligner",
        "deduper",
        "output_type",
        "exists",
        "size_bytes",
        "source_path",
    ]
    rows = [_infer_record(args.stage, path) for path in args.paths]
    rows.sort(
        key=lambda row: (
            str(row["sample"]),
            str(row["tool"]),
            str(row["aligner"]),
            str(row["deduper"]),
            str(row["output_type"]),
            str(row["source_path"]),
        )
    )

    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
