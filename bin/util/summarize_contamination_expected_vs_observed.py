#!/usr/bin/env python3
"""Summarize synthetic contamination expectations against QC outputs."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


DEFAULT_SYNTHETIC_ROOT = "/fsx/scratch/dayoa_qc_contam/giab_hg002_hg003_5x_20260425"

OUTPUT_HEADER = [
    "sample_id",
    "expected_contamination_pct",
    "gatk_freemix",
    "gatk_contamination_pct",
    "gatk_delta_pct",
    "gatk_path",
    "verifybamid2_freemix",
    "verifybamid2_contamination_pct",
    "verifybamid2_delta_pct",
    "verifybamid2_path",
]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create observed_vs_expected_contam.tsv for synthetic contamination outputs."
    )
    parser.add_argument("--synthetic-root", default=DEFAULT_SYNTHETIC_ROOT)
    parser.add_argument(
        "--plan",
        default=None,
        help="Path to contamination_plan.tsv. Defaults to SYNTHETIC_ROOT/contamination_plan.tsv.",
    )
    parser.add_argument("--results-root", required=True)
    parser.add_argument("--aligner", default="sent")
    parser.add_argument("--deduper", default="dmd")
    parser.add_argument("--verifybamid2-panel", default="100k")
    parser.add_argument(
        "--output",
        default=None,
        help="Output TSV. Defaults to SYNTHETIC_ROOT/observed_vs_expected_contam.tsv.",
    )
    return parser.parse_args(argv)


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_HEADER, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def first_existing(paths: list[Path]) -> Path | None:
    for path in paths:
        if path.is_file() and path.stat().st_size > 0:
            return path
    return None


def find_contam_file(
    results_root: Path,
    sample_id: str,
    aligner: str,
    deduper: str,
    tool: str,
    verifybamid2_panel: str,
) -> Path | None:
    if tool == "vb2":
        pattern = (
            f"*{sample_id}*/align/{aligner}/{deduper}/alignqc/contam/vb2/"
            f"{verifybamid2_panel}/*.{aligner}.{deduper}.{verifybamid2_panel}.vb2.tsv"
        )
    else:
        pattern = (
            f"*{sample_id}*/align/{aligner}/{deduper}/alignqc/contam/{tool}/"
            f"*.{aligner}.{deduper}.{tool}.tsv"
        )
    return first_existing(sorted(results_root.glob(pattern)))


def read_freemix(path: Path | None) -> str:
    if path is None:
        return ""
    rows = read_tsv(path)
    if not rows:
        return ""
    row = rows[0]
    for key in (
        "contamination_fraction",
        "freemix_fraction",
        "FREEMIX",
        "freemix",
        "contamination",
        "CONTAMINATION",
    ):
        value = row.get(key)
        if value not in (None, ""):
            return value
    return ""


def freemix_to_pct(value: str) -> str:
    if not value:
        return ""
    return f"{float(value) * 100:.6g}"


def delta_pct(observed_pct: str, expected_pct: str) -> str:
    if not observed_pct:
        return ""
    return f"{float(observed_pct) - float(expected_pct):.6g}"


def build_summary(
    plan_rows: list[dict[str, str]],
    results_root: Path,
    aligner: str,
    deduper: str,
    verifybamid2_panel: str,
) -> list[dict[str, str]]:
    summary = []
    for plan_row in plan_rows:
        sample_id = plan_row["sample_id"]
        expected_pct = plan_row["contamination_percent"]
        gatk_path = find_contam_file(
            results_root, sample_id, aligner, deduper, "gatk", verifybamid2_panel
        )
        vb2_path = find_contam_file(
            results_root, sample_id, aligner, deduper, "vb2", verifybamid2_panel
        )
        gatk_freemix = read_freemix(gatk_path)
        vb2_freemix = read_freemix(vb2_path)
        gatk_pct = freemix_to_pct(gatk_freemix)
        vb2_pct = freemix_to_pct(vb2_freemix)
        summary.append(
            {
                "sample_id": sample_id,
                "expected_contamination_pct": expected_pct,
                "gatk_freemix": gatk_freemix,
                "gatk_contamination_pct": gatk_pct,
                "gatk_delta_pct": delta_pct(gatk_pct, expected_pct),
                "gatk_path": str(gatk_path or ""),
                "verifybamid2_freemix": vb2_freemix,
                "verifybamid2_contamination_pct": vb2_pct,
                "verifybamid2_delta_pct": delta_pct(vb2_pct, expected_pct),
                "verifybamid2_path": str(vb2_path or ""),
            }
        )
    return summary


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    synthetic_root = Path(args.synthetic_root)
    plan_path = Path(args.plan) if args.plan else synthetic_root / "contamination_plan.tsv"
    output_path = Path(args.output) if args.output else synthetic_root / "observed_vs_expected_contam.tsv"
    results_root = Path(args.results_root)

    if not plan_path.is_file():
        print(f"ERROR: missing contamination plan: {plan_path}", file=sys.stderr)
        return 2
    if not results_root.is_dir():
        print(f"ERROR: missing results root: {results_root}", file=sys.stderr)
        return 2

    summary = build_summary(
        read_tsv(plan_path),
        results_root,
        args.aligner,
        args.deduper,
        args.verifybamid2_panel,
    )
    write_tsv(output_path, summary)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
