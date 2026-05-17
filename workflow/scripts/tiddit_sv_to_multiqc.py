#!/usr/bin/env python3
"""Summarize TIDDIT SV VCFs as a MultiQC custom-data TSV."""

from __future__ import annotations

import argparse
import csv
import gzip
import re
from pathlib import Path
from typing import TextIO


TIDDIT_PATH_RE = re.compile(
    r"(?P<sample>[^/]+)/align/(?P<aligner>[^/]+)/(?P<deduper>[^/]+)/sv/tiddit/"
)
SVTYPE_KEYS = ("DEL", "DUP", "INV", "INS", "BND", "TRA")
FIELDNAMES = [
    "Sample",
    "base_sample",
    "aligner",
    "deduper",
    "sv_caller",
    "total_records",
    "DEL",
    "DUP",
    "INV",
    "INS",
    "BND",
    "TRA",
    "other_svtype",
    "no_svtype",
    "vcf_path",
    "status",
]


def stage_sample_id(sample: str, aligner: str, deduper: str, sv_caller: str) -> str:
    return ".".join([sample, aligner, deduper, sv_caller])


def parse_tiddit_path(path: str) -> tuple[str, str, str]:
    match = TIDDIT_PATH_RE.search(path)
    if not match:
        raise ValueError(f"Malformed TIDDIT VCF path: {path}")
    return match.group("sample"), match.group("aligner"), match.group("deduper")


def open_text(path: Path) -> TextIO:
    if path.name.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8")
    return path.open("r", encoding="utf-8")


def parse_info_svtype(info: str) -> str:
    for part in info.split(";"):
        if part.startswith("SVTYPE="):
            return part.split("=", 1)[1].strip()
    return ""


def summarize_vcf(path_text: str) -> dict[str, str | int]:
    sample, aligner, deduper = parse_tiddit_path(path_text)
    path = Path(path_text)
    counts = {key: 0 for key in SVTYPE_KEYS}
    total_records = 0
    other_svtype = 0
    no_svtype = 0
    status = "ok"

    if not path.exists():
        status = "missing"
    else:
        with open_text(path) as handle:
            for line in handle:
                if not line or line.startswith("#"):
                    continue
                total_records += 1
                fields = line.rstrip("\n").split("\t")
                svtype = parse_info_svtype(fields[7] if len(fields) > 7 else "")
                if not svtype:
                    no_svtype += 1
                elif svtype in counts:
                    counts[svtype] += 1
                else:
                    other_svtype += 1
        if total_records == 0:
            status = "no_records"

    return {
        "Sample": stage_sample_id(sample, aligner, deduper, "tiddit"),
        "base_sample": sample,
        "aligner": aligner,
        "deduper": deduper,
        "sv_caller": "tiddit",
        "total_records": total_records,
        "DEL": counts["DEL"],
        "DUP": counts["DUP"],
        "INV": counts["INV"],
        "INS": counts["INS"],
        "BND": counts["BND"],
        "TRA": counts["TRA"],
        "other_svtype": other_svtype,
        "no_svtype": no_svtype,
        "vcf_path": path_text,
        "status": status,
    }


def write_summary(paths: list[str], output: str) -> None:
    rows = [summarize_vcf(path) for path in paths]
    rows.sort(key=lambda row: str(row["Sample"]))
    out_path = Path(output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("vcfs", nargs="*")
    args = parser.parse_args()
    write_summary(args.vcfs, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
