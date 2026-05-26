#!/usr/bin/env python3
"""Write a mounted Illumina run-QC JSON summary from RunInfo and InterOp tables."""

from __future__ import annotations

import argparse
import csv
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def _require_file(path_text: str, label: str) -> Path:
    path = Path(path_text)
    if not path.is_file():
        raise SystemExit(f"{label} does not exist: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"{label} is empty: {path}")
    return path


def _count_rows(path: Path) -> int:
    with path.open(newline="", encoding="utf-8") as handle:
        return sum(1 for row in csv.reader(handle) if any(cell.strip() for cell in row))


def _runinfo_summary(path: Path) -> dict[str, object]:
    root = ET.parse(path).getroot()
    run = root.find("Run")
    if run is None:
        raise SystemExit(f"RunInfo.xml is missing Run element: {path}")

    reads = []
    reads_node = run.find("Reads")
    if reads_node is not None:
        for read in reads_node.findall("Read"):
            reads.append(dict(read.attrib))

    flowcell_layout = {}
    layout = run.find("FlowcellLayout")
    if layout is not None:
        flowcell_layout = dict(layout.attrib)

    return {
        "run_id": run.attrib.get("Id", ""),
        "run_number": run.attrib.get("Number", ""),
        "flowcell": (run.findtext("Flowcell") or ""),
        "instrument": (run.findtext("Instrument") or ""),
        "date": (run.findtext("Date") or ""),
        "reads": reads,
        "flowcell_layout": flowcell_layout,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-info", required=True)
    parser.add_argument("--interop-summary", required=True)
    parser.add_argument("--interop-index-summary", required=True)
    parser.add_argument("--output-json", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_info = _require_file(args.run_info, "RunInfo.xml")
    interop_summary = _require_file(args.interop_summary, "interop_summary")
    interop_index_summary = _require_file(
        args.interop_index_summary, "interop_index_summary"
    )
    output = Path(args.output_json)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "platform": "ILMN",
                "run_info": _runinfo_summary(run_info),
                "interop_summary": str(interop_summary),
                "interop_summary_rows": _count_rows(interop_summary),
                "interop_index_summary": str(interop_index_summary),
                "interop_index_summary_rows": _count_rows(interop_index_summary),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
