#!/usr/bin/env python3
"""Write explicit MultiQC custom-content inputs for Illumina run QC."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


KEY_ORDER = (
    "platform",
    "run_s3_uri",
    "interop_summary_rows",
    "interop_index_summary_rows",
    "json_error_mentions",
    "json_fail_mentions",
    "json_warning_mentions",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary-tsv", required=True)
    parser.add_argument("--illumina-qc-json", required=True)
    parser.add_argument("--summary-out", required=True)
    parser.add_argument("--config-out", required=True)
    return parser.parse_args()


def require_file(path_text: str, label: str) -> Path:
    path = Path(path_text)
    if not path.is_file():
        raise SystemExit(f"{label} does not exist: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"{label} is empty: {path}")
    return path


def read_summary(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames != ["metric", "value"]:
            raise SystemExit(
                f"summary TSV must have exactly metric/value columns: {path}"
            )
        rows = {
            str(row.get("metric", "")).strip(): str(row.get("value", "")).strip()
            for row in reader
            if str(row.get("metric", "")).strip()
        }
    if not rows:
        raise SystemExit(f"summary TSV has no metric rows: {path}")
    return rows


def read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"illumina QC JSON root must be an object: {path}")
    return data


def run_id_from_json(data: dict[str, Any]) -> str:
    run_info = data.get("run_info")
    if isinstance(run_info, dict):
        for key in ("run_id", "flowcell"):
            value = str(run_info.get(key, "")).strip()
            if value:
                return sanitize_sample_id(value)
    return "illumina_run_qc"


def sanitize_sample_id(value: str) -> str:
    text = re.sub(r"[^A-Za-z0-9._-]+", "_", str(value).strip())
    text = re.sub(r"_+", "_", text)
    return text.strip("._-") or "illumina_run_qc"


def write_summary_table(path: Path, sample_id: str, rows: dict[str, str]) -> None:
    keys = [key for key in KEY_ORDER if key in rows]
    keys.extend(sorted(key for key in rows if key not in set(keys)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["Sample", *keys], delimiter="\t", lineterminator="\n"
        )
        writer.writeheader()
        writer.writerow({"Sample": sample_id, **{key: rows.get(key, "") for key in keys}})


def write_multiqc_config(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        """custom_data:
  illumina_run_qc_summary:
    id: illumina_run_qc_summary
    section_name: Illumina Run QC Summary
    parent_id: dayoa_input_demux_read_qc
    parent_name: Input, demux, read QC, trimming
    description: Mounted Illumina run QC summary generated from explicit run context inputs
    file_format: tsv
    plot_type: table
    pconfig:
      id: illumina_run_qc_summary
sp:
  illumina_run_qc_summary:
    fn: illumina_run_qc_summary_mqc.tsv
""",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    summary_path = require_file(args.summary_tsv, "summary TSV")
    json_path = require_file(args.illumina_qc_json, "illumina QC JSON")
    summary = read_summary(summary_path)
    qc_json = read_json(json_path)
    sample_id = run_id_from_json(qc_json)
    write_summary_table(Path(args.summary_out), sample_id, summary)
    write_multiqc_config(Path(args.config_out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
