#!/usr/bin/env python3
"""Create small run-level QC report artifacts from explicit vendor inputs."""

from __future__ import annotations

import argparse
import csv
import html
import json
from pathlib import Path
from typing import Any


def _require_text(value: str | None, label: str) -> str:
    text = str(value or "").strip()
    if not text:
        raise SystemExit(f"{label} is required")
    return text


def _require_file(path_text: str | None, label: str) -> Path:
    text = _require_text(path_text, label)
    path = Path(text)
    if not path.exists():
        raise SystemExit(f"{label} does not exist: {path}")
    if not path.is_file():
        raise SystemExit(f"{label} is not a file: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"{label} is empty: {path}")
    return path


def _count_rows(path: Path) -> int:
    with path.open(newline="", encoding="utf-8") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t")
        except csv.Error:
            dialect = csv.excel_tab if "\t" in sample else csv.excel
        reader = csv.reader(handle, dialect)
        return sum(1 for row in reader if any(cell.strip() for cell in row))


def _read_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc


def _walk_json(value: Any) -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            found.append(str(key))
            found.extend(_walk_json(item))
    elif isinstance(value, list):
        for item in value:
            found.extend(_walk_json(item))
    else:
        found.append(str(value))
    return found


def _json_signal_counts(value: Any) -> dict[str, int]:
    tokens = [token.lower() for token in _walk_json(value)]
    return {
        "json_error_mentions": sum("error" in token for token in tokens),
        "json_warning_mentions": sum("warn" in token for token in tokens),
        "json_fail_mentions": sum("fail" in token for token in tokens),
    }


def _write_tsv(path: Path, rows: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["metric", "value"])
        writer.writerows(rows)


def _write_html(path: Path, title: str, rows: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    table_rows = "\n".join(
        "<tr><th>{}</th><td>{}</td></tr>".format(
            html.escape(metric), html.escape(value)
        )
        for metric, value in rows
    )
    content = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 2rem; color: #1f2933; }}
    h1 {{ font-size: 1.35rem; margin-bottom: 1rem; }}
    table {{ border-collapse: collapse; min-width: 40rem; max-width: 100%; }}
    th, td {{ border: 1px solid #c9d2dc; padding: 0.45rem 0.6rem; text-align: left; }}
    th {{ background: #eef3f8; width: 18rem; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  <table>
    <tbody>
{table_rows}
    </tbody>
  </table>
</body>
</html>
"""
    path.write_text(content, encoding="utf-8")


def _illumina_rows(args: argparse.Namespace) -> list[tuple[str, str]]:
    run_s3_uri = _require_text(args.run_s3_uri, "run_s3_uri")
    interop_summary = _require_file(args.interop_summary, "interop_summary")
    interop_index_summary = _require_file(
        args.interop_index_summary, "interop_index_summary"
    )
    illumina_qc_json = _require_file(args.illumina_qc_json, "illumina_qc_json")
    illumina_qc = _read_json(illumina_qc_json)
    signal_counts = _json_signal_counts(illumina_qc)
    rows = [
        ("platform", "ILMN"),
        ("run_s3_uri", run_s3_uri),
        ("interop_summary", str(interop_summary)),
        ("interop_summary_rows", str(_count_rows(interop_summary))),
        ("interop_index_summary", str(interop_index_summary)),
        ("interop_index_summary_rows", str(_count_rows(interop_index_summary))),
        ("illumina_qc_json", str(illumina_qc_json)),
    ]
    rows.extend((key, str(value)) for key, value in sorted(signal_counts.items()))
    return rows


def _placeholder_rows(args: argparse.Namespace, platform: str) -> list[tuple[str, str]]:
    metric_label = {
        "ONT": "run_qc.ont.metrics_path",
        "UG": "run_qc.ultima.metrics_path",
    }[platform]
    metrics = _require_file(args.metrics_path, metric_label)
    run_uri = str(args.run_s3_uri or "").strip()
    rows = [
        ("platform", platform),
        ("metrics_path", str(metrics)),
        ("metrics_rows", str(_count_rows(metrics))),
    ]
    if run_uri:
        rows.append(("run_s3_uri", run_uri))
    if metrics.suffix.lower() == ".json":
        signals = _json_signal_counts(_read_json(metrics))
        rows.extend((key, str(value)) for key, value in sorted(signals.items()))
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=["ILMN", "ONT", "UG"])
    parser.add_argument("--run-s3-uri", default="")
    parser.add_argument("--interop-summary", default="")
    parser.add_argument("--interop-index-summary", default="")
    parser.add_argument("--illumina-qc-json", default="")
    parser.add_argument("--metrics-path", default="")
    parser.add_argument("--output-html", required=True)
    parser.add_argument("--output-tsv", required=True)
    parser.add_argument("--done", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.platform == "ILMN":
        rows = _illumina_rows(args)
        title = "Illumina Run QC Report"
    elif args.platform == "ONT":
        rows = _placeholder_rows(args, "ONT")
        title = "ONT Run QC Report"
    else:
        rows = _placeholder_rows(args, "UG")
        title = "Ultima Run QC Report"

    html_path = Path(args.output_html)
    tsv_path = Path(args.output_tsv)
    done_path = Path(args.done)
    _write_tsv(tsv_path, rows)
    _write_html(html_path, title, rows)
    done_path.parent.mkdir(parents=True, exist_ok=True)
    done_path.write_text("done\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
