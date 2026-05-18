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


def _sample_id(sample: str, aligner: str, deduper: str) -> str:
    if aligner != "NA" and deduper != "NA":
        return f"{sample}.{aligner}.{deduper}"
    return sample


def _summary_id(stage: str, path: Path) -> str:
    stem = path.name
    for suffix in ("_mqc.tsv", ".mqc.tsv", "_mqc.csv", ".mqc.csv"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    else:
        stem = path.stem
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", stem).strip("._-")
    return f"{stage}.{stem or 'summary'}"


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
    if sample == "NA":
        sample_id = _summary_id(stage, path)
        if tool == "unknown":
            tool = path.stem
        base_sample = ""
        aligner = ""
        deduper = ""
    else:
        sample_id = _sample_id(sample, aligner, deduper)
        base_sample = sample

    try:
        stat = path.stat()
        exists = "yes"
        size_bytes = stat.st_size
    except OSError:
        exists = "no"
        size_bytes = 0

    return {
        "Sample": sample_id,
        "base_sample": base_sample,
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
        "Sample",
        "base_sample",
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
            str(row["Sample"]),
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
