#!/usr/bin/env python3
"""Compile contamination QC outputs into MultiQC-ready custom TSVs."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


CONTAMINATION_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "panel_id",
    "panel_label",
    "tool",
    "method",
    "contamination_fraction",
    "contamination_pct",
    "ci_low_fraction",
    "ci_high_fraction",
    "unknown_contamination_fraction",
    "unknown_contamination_pct",
    "site_count",
    "read_count",
    "mean_depth",
    "svd_prefix",
    "source_path",
    "status",
]

DONOR_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "source_rank",
    "source_sample_id",
    "is_unknown_source",
    "contamination_fraction",
    "contamination_pct",
    "single_source_delta_log_likelihood",
    "source_path",
]


def _safe_pct(value: str | None) -> str:
    try:
        return str(float(value) * 100.0)
    except (TypeError, ValueError):
        return ""


def _seconds_to_minutes(value: str | None) -> str:
    try:
        return str(float(value) / 60.0)
    except (TypeError, ValueError):
        return ""


def _stage_sample_id(sample: str, aligner: str, deduper: str) -> str:
    return ".".join(part for part in [sample, aligner, deduper] if part)


def _path_context(path: str) -> tuple[str, str, str]:
    parts = Path(path).parts
    for index, part in enumerate(parts):
        if part == "align" and index >= 1 and index + 2 < len(parts):
            return parts[index - 1], parts[index + 1], parts[index + 2]
    raise ValueError(f"Malformed contamination path: {path}")


def _parse_contam_path(path: str, sample_map: dict[str, str]) -> tuple[str, str, str, str]:
    sample, aligner, deduper = _path_context(path)
    return sample, sample_map.get(sample, sample), aligner, deduper


def _read_first_row(path: str) -> dict[str, str]:
    try:
        with open(path, newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
    except OSError:
        return {}
    return rows[0] if rows else {}


def _write_header(path: str, fieldnames: list[str]) -> tuple[csv.DictWriter, object]:
    out_path = Path(path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    handle = out_path.open("w", newline="", encoding="utf-8")
    writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    return writer, handle


def compile_reports(args: argparse.Namespace) -> None:
    sample_map = json.loads(args.sample_map_json)
    contam_writer, contam_handle = _write_header(
        args.contamination_output, CONTAMINATION_FIELDS
    )
    site_writer, site_handle = _write_header(args.site_mix_output, CONTAMINATION_FIELDS)
    donor_writer, donor_handle = _write_header(args.donor_output, DONOR_FIELDS)

    try:
        for path in args.gatk:
            sample, external, aligner, deduper = _parse_contam_path(path, sample_map)
            sample_id = _stage_sample_id(sample, aligner, deduper)
            row = _read_first_row(path)
            freemix = row.get("FREEMIX", "")
            contam_writer.writerow(
                {
                    "Sample": sample_id,
                    "base_sample": sample,
                    "sample_id": sample,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "panel_id": "",
                    "panel_label": "",
                    "tool": "gatk",
                    "method": "freemix",
                    "contamination_fraction": freemix,
                    "contamination_pct": _safe_pct(freemix),
                    "ci_low_fraction": "",
                    "ci_high_fraction": "",
                    "unknown_contamination_fraction": "",
                    "unknown_contamination_pct": "",
                    "site_count": row.get("#SNPS", ""),
                    "read_count": row.get("#READS", ""),
                    "mean_depth": row.get("AVG_DP", ""),
                    "svd_prefix": "",
                    "source_path": path,
                    "status": "ok" if freemix not in ["", "NA"] else "no_call",
                }
            )

        for path in args.site_mix:
            sample, external, aligner, deduper = _parse_contam_path(path, sample_map)
            sample_id = _stage_sample_id(sample, aligner, deduper)
            row = _read_first_row(path)
            out_row = {
                "Sample": sample_id,
                "base_sample": sample,
                "sample_id": sample,
                "external_sample_id": external,
                "aligner": aligner,
                "deduper": deduper,
                "panel_id": "",
                "panel_label": "",
                "tool": "site_mix",
                "method": row.get("method", "genotype_free_site_mix"),
                "contamination_fraction": row.get("contamination_fraction", ""),
                "contamination_pct": row.get("contamination_pct", ""),
                "ci_low_fraction": row.get("ci_low_fraction", ""),
                "ci_high_fraction": row.get("ci_high_fraction", ""),
                "unknown_contamination_fraction": row.get(
                    "unknown_contamination_fraction", ""
                ),
                "unknown_contamination_pct": row.get("unknown_contamination_pct", ""),
                "site_count": row.get("site_count", ""),
                "read_count": row.get("read_count", ""),
                "mean_depth": row.get("mean_depth", ""),
                "svd_prefix": "",
                "source_path": path,
                "status": "ok"
                if row.get("contamination_fraction", "") not in ["", "NA"]
                else "no_call",
            }
            contam_writer.writerow(out_row)
            site_writer.writerow(out_row)

        for path in args.site_mix_donors:
            sample, external, aligner, deduper = _parse_contam_path(path, sample_map)
            sample_id = _stage_sample_id(sample, aligner, deduper)
            with open(path, newline="", encoding="utf-8") as handle:
                for row in csv.DictReader(handle, delimiter="\t"):
                    donor_writer.writerow(
                        {
                            "Sample": sample_id,
                            "base_sample": sample,
                            "sample_id": sample,
                            "external_sample_id": external,
                            "aligner": aligner,
                            "deduper": deduper,
                            "source_rank": row.get("source_rank", ""),
                            "source_sample_id": row.get("source_sample_id", ""),
                            "is_unknown_source": row.get("is_unknown_source", ""),
                            "contamination_fraction": row.get(
                                "contamination_fraction", ""
                            ),
                            "contamination_pct": row.get("contamination_pct", ""),
                            "single_source_delta_log_likelihood": row.get(
                                "single_source_delta_log_likelihood", ""
                            ),
                            "source_path": path,
                        }
                    )
    finally:
        for handle in (contam_handle, site_handle, donor_handle):
            handle.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-map-json", required=True)
    parser.add_argument("--contamination-output", required=True)
    parser.add_argument("--site-mix-output", required=True)
    parser.add_argument("--donor-output", required=True)
    parser.add_argument("--gatk", nargs="*", default=[])
    parser.add_argument("--site-mix", nargs="*", default=[])
    parser.add_argument("--site-mix-donors", nargs="*", default=[])
    args = parser.parse_args()
    compile_reports(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
