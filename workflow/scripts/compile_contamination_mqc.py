#!/usr/bin/env python3
"""Compile contamination QC outputs into MultiQC-ready custom TSVs."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


CONTAMINATION_FIELDS = [
    "Sample",
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

VB2_FIELDS = [
    "Sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "panel_id",
    "panel_label",
    "snp_count",
    "svd_prefix",
    "freemix_fraction",
    "contamination_pct",
    "site_count",
    "read_count",
    "mean_depth",
    "runtime_seconds",
    "runtime_minutes",
    "task_cost",
    "source_path",
    "benchmark_path",
    "status",
]

DONOR_FIELDS = [
    "Sample",
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


def _parse_vb2_panel_path(
    path: str, sample_map: dict[str, str]
) -> tuple[str, str, str, str, str]:
    sample, external, aligner, deduper = _parse_contam_path(path, sample_map)
    parts = list(Path(path).parts)
    try:
        panel = parts[parts.index("vb2") + 1]
    except (ValueError, IndexError) as exc:
        raise ValueError(f"Malformed panel-aware VerifyBamID2 path: {path}") from exc
    return sample, external, aligner, deduper, panel


def _parse_benchmark_path(path: str) -> tuple[str, str, str, str] | None:
    name = Path(path).name
    suffix = ".vb2.bench.tsv"
    if not name.endswith(suffix):
        return None
    stem = name[: -len(suffix)]
    try:
        sample, aligner, deduper, panel = stem.rsplit(".", 3)
    except ValueError:
        return None
    return sample, aligner, deduper, panel


def _read_first_row(path: str) -> dict[str, str]:
    try:
        with open(path, newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
    except OSError:
        return {}
    return rows[0] if rows else {}


def _benchmark_by_vb2_key(paths: list[str]) -> dict[tuple[str, str, str, str], str]:
    benchmarks: dict[tuple[str, str, str, str], str] = {}
    for path in paths:
        key = _parse_benchmark_path(path)
        if key is not None:
            benchmarks[key] = path
    return benchmarks


def _write_header(path: str, fieldnames: list[str]) -> csv.DictWriter:
    out_path = Path(path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    handle = out_path.open("w", newline="", encoding="utf-8")
    writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    writer._dayoa_handle = handle  # type: ignore[attr-defined]
    return writer


def _close_writer(writer: csv.DictWriter) -> None:
    handle = getattr(writer, "_dayoa_handle")
    handle.close()


def compile_reports(args: argparse.Namespace) -> None:
    sample_map = json.loads(args.sample_map_json)
    panel_metadata = json.loads(args.panel_metadata_json)
    contam_writer = _write_header(args.contamination_output, CONTAMINATION_FIELDS)
    site_writer = _write_header(args.site_mix_output, CONTAMINATION_FIELDS)
    vb2_writer = _write_header(args.vb2_comparison_output, VB2_FIELDS)
    donor_writer = _write_header(args.donor_output, DONOR_FIELDS)

    try:
        vb2_benchmarks = _benchmark_by_vb2_key(args.vb2_bench)
        for path in args.vb2:
            sample, external, aligner, deduper, panel_id = _parse_vb2_panel_path(
                path, sample_map
            )
            sample_id = _stage_sample_id(sample, aligner, deduper)
            row = _read_first_row(path)
            freemix = row.get("FREEMIX", "")
            panel_cfg = panel_metadata.get(panel_id, {})
            benchmark_path = vb2_benchmarks.get((sample, aligner, deduper, panel_id), "")
            benchmark = _read_first_row(benchmark_path)
            runtime_seconds = benchmark.get("s", "")
            panel_label = str(panel_cfg.get("label", panel_id))
            snp_count = str(panel_cfg.get("snp_count", row.get("#SNPS", "")))
            svd_prefix = str(panel_cfg.get("svd_prefix", ""))
            contam_row = {
                "Sample": sample_id,
                "sample_id": sample_id,
                "external_sample_id": external,
                "aligner": aligner,
                "deduper": deduper,
                "panel_id": panel_id,
                "panel_label": panel_label,
                "tool": "verifybamid2",
                "method": "freemix",
                "contamination_fraction": freemix,
                "contamination_pct": _safe_pct(freemix),
                "ci_low_fraction": "",
                "ci_high_fraction": "",
                "unknown_contamination_fraction": "",
                "unknown_contamination_pct": "",
                "site_count": row.get("#SNPS", snp_count),
                "read_count": row.get("#READS", ""),
                "mean_depth": row.get("AVG_DP", ""),
                "svd_prefix": svd_prefix,
                "source_path": path,
                "status": "ok" if freemix not in ["", "NA"] else "no_call",
            }
            contam_writer.writerow(contam_row)
            vb2_writer.writerow(
                {
                    "Sample": sample_id,
                    "sample_id": sample_id,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "panel_id": panel_id,
                    "panel_label": panel_label,
                    "snp_count": snp_count,
                    "svd_prefix": svd_prefix,
                    "freemix_fraction": freemix,
                    "contamination_pct": _safe_pct(freemix),
                    "site_count": row.get("#SNPS", snp_count),
                    "read_count": row.get("#READS", ""),
                    "mean_depth": row.get("AVG_DP", ""),
                    "runtime_seconds": runtime_seconds,
                    "runtime_minutes": _seconds_to_minutes(runtime_seconds),
                    "task_cost": benchmark.get("task_cost", ""),
                    "source_path": path,
                    "benchmark_path": benchmark_path,
                    "status": contam_row["status"],
                }
            )

        for path in args.gatk:
            sample, external, aligner, deduper = _parse_contam_path(path, sample_map)
            sample_id = _stage_sample_id(sample, aligner, deduper)
            row = _read_first_row(path)
            freemix = row.get("FREEMIX", "")
            contam_writer.writerow(
                {
                    "Sample": sample_id,
                    "sample_id": sample_id,
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
                "sample_id": sample_id,
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
                            "sample_id": sample_id,
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
        for writer in (contam_writer, site_writer, vb2_writer, donor_writer):
            _close_writer(writer)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-map-json", required=True)
    parser.add_argument("--panel-metadata-json", required=True)
    parser.add_argument("--contamination-output", required=True)
    parser.add_argument("--vb2-comparison-output", required=True)
    parser.add_argument("--site-mix-output", required=True)
    parser.add_argument("--donor-output", required=True)
    parser.add_argument("--vb2", nargs="*", default=[])
    parser.add_argument("--vb2-bench", nargs="*", default=[])
    parser.add_argument("--gatk", nargs="*", default=[])
    parser.add_argument("--site-mix", nargs="*", default=[])
    parser.add_argument("--site-mix-donors", nargs="*", default=[])
    args = parser.parse_args()
    compile_reports(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
