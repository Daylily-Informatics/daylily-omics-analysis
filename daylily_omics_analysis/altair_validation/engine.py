from __future__ import annotations

import csv
import gzip
import hashlib
import json
import math
import re
import shutil
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape


EXPECTED_GIAB_IDS = ("HG001", "HG002", "HG003", "HG004", "HG005", "HG006", "HG007")
EXPECTED_RR_CHROMOSOMES = tuple([f"chr{i}" for i in range(1, 23)] + ["chrX"])
ACCURACY_GROUPS = {
    "SNV": ("SNPts", "SNPtv"),
    "small_indel_le50": ("INS_50", "DEL_50", "Indel_50"),
}
GT50_CLASSES = {"INS_gt50", "DEL_gt50", "Indel_gt50"}
OUTPUT_FILENAMES = (
    "rr_manifest.tsv",
    "bar_manifest.tsv",
    "accuracy_metrics_by_sample.tsv",
    "accuracy_metrics_pooled.tsv",
    "rr_coverage_callability_by_sample.tsv",
    "rr_boundary_verification.tsv",
    "validation_summary.json",
)
RR_MANIFEST_FIELDS = (
    "rr_bed_name",
    "rr_bed_path",
    "rr_bed_sha256",
    "rr_row_count",
    "rr_total_bases",
    "genome_build",
    "expected_chromosomes",
    "observed_chromosomes",
    "missing_chromosomes",
    "extra_chromosomes",
    "source_artifact",
    "approval_record",
    "status",
    "reason",
)
BAR_MANIFEST_FIELDS = (
    "sample_id",
    "rr_bed_name",
    "rr_bed_sha256",
    "giab_hc_bed_name",
    "giab_hc_bed_sha256",
    "bar_bed_name",
    "bar_bed_sha256",
    "bar_row_count",
    "bar_total_bases",
    "chromosome_set",
    "status",
    "reason",
)
ACCURACY_SAMPLE_FIELDS = (
    "sample_id",
    "variant_class",
    "tp",
    "fp",
    "fn",
    "sensitivity",
    "ppv",
    "denominator_bed_name",
    "denominator_bed_sha256",
    "source_concordance_rows",
    "status",
    "reason",
)
ACCURACY_POOLED_FIELDS = (
    "variant_class",
    "tp",
    "fp",
    "fn",
    "sensitivity",
    "ppv",
    "sample_count",
    "source_concordance_rows",
    "status",
    "reason",
)
COVERAGE_FIELDS = (
    "sample_id",
    "run_id",
    "library_id",
    "rr_bed_name",
    "rr_bed_sha256",
    "rr_total_bases",
    "median_rr_depth",
    "mean_rr_depth",
    "pct_rr_bases_ge_10x",
    "pct_rr_bases_ge_20x",
    "callable_fraction",
    "callable_definition",
    "coverage_tool",
    "coverage_tool_version",
    "status",
    "reason",
)
BOUNDARY_FIELDS = (
    "sample_id",
    "released_vcf",
    "rr_bed_name",
    "rr_bed_sha256",
    "total_released_calls",
    "calls_outside_rr",
    "released_indels_gt50",
    "status",
    "reason",
)
FORBIDDEN_COVERAGE_PATH_TOKENS = (
    "altair_rr_v1_x_giab",
    "benchmark_accuracy_region",
    "giabhc",
    "giab_hc",
    "giab-hc",
    "highconfidence",
    "high_confidence",
    "bar",
    "clinvar",
    "whole_genome",
    "whole-genome",
    "wgs",
    "core",
)


class AltairValidationError(ValueError):
    """Raised when Altair validation inputs violate the validation contract."""


@dataclass(frozen=True)
class AltairValidationInputs:
    rr_manifest: Path
    bar_manifest: Path
    giab_concordance: tuple[Path, ...]
    output_dir: Path
    rr_coverage_callability: Path | None = None
    boundary_verification: Path | None = None
    report_template_docx: Path | None = None
    report_docx: Path | None = None
    expected_samples: tuple[str, ...] = EXPECTED_GIAB_IDS


def build_validation_artifacts(inputs: AltairValidationInputs) -> dict[str, object]:
    rr_rows = normalize_rr_manifest(_read_tsv(inputs.rr_manifest))
    bar_rows = normalize_bar_manifest(_read_tsv(inputs.bar_manifest))
    concordance_rows = _read_many_tsv(inputs.giab_concordance)

    accuracy_rows, invalid_denominators = build_accuracy_by_sample(
        bar_rows=bar_rows,
        concordance_rows=concordance_rows,
        expected_samples=inputs.expected_samples,
    )
    pooled_rows = build_pooled_accuracy(
        accuracy_rows, expected_samples=inputs.expected_samples
    )
    coverage_rows = normalize_coverage_rows(inputs.rr_coverage_callability)
    boundary_rows = normalize_boundary_rows(inputs.boundary_verification)

    reasons = collect_reasons(
        rr_rows=rr_rows,
        bar_rows=bar_rows,
        accuracy_rows=accuracy_rows,
        pooled_rows=pooled_rows,
        coverage_rows=coverage_rows,
        boundary_rows=boundary_rows,
        invalid_denominators=invalid_denominators,
        expected_samples=inputs.expected_samples,
    )
    summary = build_summary(
        rr_rows=rr_rows,
        bar_rows=bar_rows,
        accuracy_rows=accuracy_rows,
        pooled_rows=pooled_rows,
        coverage_rows=coverage_rows,
        boundary_rows=boundary_rows,
        reasons=reasons,
        expected_samples=inputs.expected_samples,
    )

    inputs.output_dir.mkdir(parents=True, exist_ok=True)
    _write_tsv(inputs.output_dir / "rr_manifest.tsv", RR_MANIFEST_FIELDS, rr_rows)
    _write_tsv(inputs.output_dir / "bar_manifest.tsv", BAR_MANIFEST_FIELDS, bar_rows)
    _write_tsv(
        inputs.output_dir / "accuracy_metrics_by_sample.tsv",
        ACCURACY_SAMPLE_FIELDS,
        accuracy_rows,
    )
    _write_tsv(
        inputs.output_dir / "accuracy_metrics_pooled.tsv",
        ACCURACY_POOLED_FIELDS,
        pooled_rows,
    )
    _write_tsv(
        inputs.output_dir / "rr_coverage_callability_by_sample.tsv",
        COVERAGE_FIELDS,
        coverage_rows,
    )
    _write_tsv(
        inputs.output_dir / "rr_boundary_verification.tsv",
        BOUNDARY_FIELDS,
        boundary_rows,
    )
    (inputs.output_dir / "validation_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if inputs.report_template_docx is not None:
        output_docx = inputs.report_docx or (
            inputs.output_dir / "QUAL-FRM-ALT-001_Altair_Validation_QC_Report.docx"
        )
        render_report_docx(
            template_docx=inputs.report_template_docx,
            output_docx=output_docx,
            summary=summary,
            rr_rows=rr_rows,
            coverage_rows=coverage_rows,
            boundary_rows=boundary_rows,
        )

    return {
        "output_dir": str(inputs.output_dir),
        "outputs": OUTPUT_FILENAMES,
        "validation_summary": summary,
    }


def normalize_rr_manifest(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    normalized = []
    for row in rows:
        item = _select_fields(row, RR_MANIFEST_FIELDS)
        expected = _chrom_list(item["expected_chromosomes"]) or list(
            EXPECTED_RR_CHROMOSOMES
        )
        observed = _chrom_list(item["observed_chromosomes"])
        if not observed and _is_present(item["rr_bed_path"]):
            observed = bed_chromosomes(Path(item["rr_bed_path"]))
        missing = [chrom for chrom in expected if chrom not in observed]
        extra = [chrom for chrom in observed if chrom not in expected]
        item["expected_chromosomes"] = _join(expected)
        item["observed_chromosomes"] = _join(observed)
        item["missing_chromosomes"] = _join(missing)
        item["extra_chromosomes"] = _join(extra)
        item["status"] = _status_value(item["status"])
        if item["status"] == "PASS" and (missing or extra):
            item["status"] = "FAIL"
            item["reason"] = _append_reason(
                item["reason"], "rr_chromosome_set_mismatch"
            )
        normalized.append(item)
    return sorted(normalized, key=lambda row: row["rr_bed_name"])


def normalize_bar_manifest(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    normalized = []
    for row in rows:
        item = _select_fields(row, BAR_MANIFEST_FIELDS)
        item["status"] = _status_value(item["status"])
        if item["sample_id"] not in EXPECTED_GIAB_IDS:
            item["status"] = "FAIL"
            item["reason"] = _append_reason(item["reason"], "unexpected_giab_sample")
        if item["status"] == "PASS" and not _is_sample_specific_bar(item):
            item["status"] = "FAIL"
            item["reason"] = _append_reason(
                item["reason"], "bar_manifest_not_sample_specific"
            )
        normalized.append(item)
    return sorted(normalized, key=lambda row: row["sample_id"])


def build_accuracy_by_sample(
    *,
    bar_rows: list[dict[str, str]],
    concordance_rows: list[dict[str, str]],
    expected_samples: tuple[str, ...] = EXPECTED_GIAB_IDS,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    allowed_denominators = _allowed_denominators(bar_rows)
    grouped: dict[tuple[str, str], dict[str, object]] = {}
    invalid_denominators = []

    for row in concordance_rows:
        sample_id = _sample_id(row)
        variant_class = _variant_class(row)
        if sample_id not in expected_samples:
            continue
        if variant_class in GT50_CLASSES or variant_class.endswith("_gt50"):
            continue
        claim_class = _claim_class(variant_class)
        if claim_class is None:
            continue

        denominator = _denominator(row)
        denominator_error = validate_accuracy_denominator(
            denominator=denominator,
            sample_id=sample_id,
            allowed_denominators=allowed_denominators,
        )
        if denominator_error:
            invalid_denominators.append(
                {
                    "sample_id": sample_id,
                    "variant_class": variant_class,
                    "accuracy_denominator": denominator,
                    "reason": denominator_error,
                    "source_row": _row_label(row),
                }
            )
            continue

        key = (sample_id, claim_class)
        if key not in grouped:
            grouped[key] = {
                "tp": 0,
                "fp": 0,
                "fn": 0,
                "source_rows": 0,
                "denominator_bed_name": _primary_bar_name(bar_rows, sample_id),
                "denominator_bed_sha256": _primary_bar_sha(bar_rows, sample_id),
            }
        grouped[key]["tp"] = int(grouped[key]["tp"]) + _int(row, "TP")
        grouped[key]["fp"] = int(grouped[key]["fp"]) + _int(row, "FP")
        grouped[key]["fn"] = int(grouped[key]["fn"]) + _int(row, "FN")
        grouped[key]["source_rows"] = int(grouped[key]["source_rows"]) + 1

    output = []
    for sample_id in expected_samples:
        for claim_class in ACCURACY_GROUPS:
            key = (sample_id, claim_class)
            if key in grouped:
                item = grouped[key]
                tp = int(item["tp"])
                fp = int(item["fp"])
                fn = int(item["fn"])
                output.append(
                    {
                        "sample_id": sample_id,
                        "variant_class": claim_class,
                        "tp": str(tp),
                        "fp": str(fp),
                        "fn": str(fn),
                        "sensitivity": _ratio(tp, tp + fn),
                        "ppv": _ratio(tp, tp + fp),
                        "denominator_bed_name": str(item["denominator_bed_name"]),
                        "denominator_bed_sha256": str(item["denominator_bed_sha256"]),
                        "source_concordance_rows": str(item["source_rows"]),
                        "status": "PASS",
                        "reason": "",
                    }
                )
            else:
                output.append(
                    {
                        "sample_id": sample_id,
                        "variant_class": claim_class,
                        "tp": "",
                        "fp": "",
                        "fn": "",
                        "sensitivity": "",
                        "ppv": "",
                        "denominator_bed_name": _primary_bar_name(bar_rows, sample_id),
                        "denominator_bed_sha256": _primary_bar_sha(bar_rows, sample_id),
                        "source_concordance_rows": "0",
                        "status": "HOLD",
                        "reason": "missing_giab_bar_metrics",
                    }
                )

    return output, sorted(
        invalid_denominators,
        key=lambda row: (
            row["sample_id"],
            row["accuracy_denominator"],
            row["variant_class"],
        ),
    )


def build_pooled_accuracy(
    rows: list[dict[str, str]],
    *,
    expected_samples: tuple[str, ...] = EXPECTED_GIAB_IDS,
) -> list[dict[str, str]]:
    pooled = []
    for claim_class in ACCURACY_GROUPS:
        source_rows = [row for row in rows if row["variant_class"] == claim_class]
        pass_rows = [row for row in source_rows if row["status"] == "PASS"]
        tp = sum(_safe_int(row["tp"]) for row in pass_rows)
        fp = sum(_safe_int(row["fp"]) for row in pass_rows)
        fn = sum(_safe_int(row["fn"]) for row in pass_rows)
        missing_samples = [
            row["sample_id"]
            for row in source_rows
            if row["status"] != "PASS" and row["sample_id"] in expected_samples
        ]
        status = "PASS" if not missing_samples else "HOLD"
        pooled.append(
            {
                "variant_class": claim_class,
                "tp": str(tp) if pass_rows else "",
                "fp": str(fp) if pass_rows else "",
                "fn": str(fn) if pass_rows else "",
                "sensitivity": _ratio(tp, tp + fn) if pass_rows else "",
                "ppv": _ratio(tp, tp + fp) if pass_rows else "",
                "sample_count": str(len(pass_rows)),
                "source_concordance_rows": str(
                    sum(
                        _safe_int(row["source_concordance_rows"]) for row in source_rows
                    )
                ),
                "status": status,
                "reason": (
                    ""
                    if status == "PASS"
                    else "missing_giab_bar_metrics:" + ",".join(missing_samples)
                ),
            }
        )
    return pooled


def validate_accuracy_denominator(
    *,
    denominator: str,
    sample_id: str,
    allowed_denominators: dict[str, set[str]],
) -> str:
    normalized = _normalize_token(denominator)
    if not normalized:
        return "invalid_accuracy_denominator:missing_denominator"
    if "clinvar" in normalized and "altair_rr_v1_x_giab_hc" not in normalized:
        return "invalid_accuracy_denominator:clinvar_only_denominator"
    if normalized in {"rr", "altair_rr", "altair_rr_v1", "reportable_range"}:
        return "invalid_accuracy_denominator:rr_only_denominator"
    if normalized in {"hg38", "b37", "genome", "whole_genome", "whole-genome"}:
        return "invalid_accuracy_denominator:genome_denominator"
    if "global" in normalized or "union" in normalized:
        return "invalid_accuracy_denominator:global_union_denominator"
    if normalized in {"giabhc", "giab_hc", "giab-high-confidence", "giab_hc_bed"}:
        return "invalid_accuracy_denominator:giab_hc_only_denominator"
    allowed = allowed_denominators.get(sample_id, set())
    if normalized not in allowed:
        return "invalid_accuracy_denominator:non_sample_specific_bar"
    return ""


def normalize_coverage_rows(path: Path | None) -> list[dict[str, str]]:
    if path is None:
        return []
    rows = []
    for row in _read_tsv(path):
        item = _select_fields(row, COVERAGE_FIELDS)
        item["status"] = _status_value(item["status"])
        candidate_paths = [
            row.get("coverage_region_path", ""),
            row.get("region_path", ""),
            row.get("rr_bed_path", ""),
            item["rr_bed_name"],
        ]
        for candidate in candidate_paths:
            if candidate:
                validate_coverage_region_path(candidate)
        missing = [
            field for field in COVERAGE_FIELDS[:-2] if not _is_present(item[field])
        ]
        if missing:
            item["status"] = "HOLD"
            item["reason"] = _append_reason(
                item["reason"],
                "missing_rr_coverage_fields:" + ",".join(missing),
            )
        rows.append(item)
    return sorted(
        rows, key=lambda row: (row["sample_id"], row["run_id"], row["library_id"])
    )


def validate_coverage_region_path(path: str) -> None:
    normalized = _normalize_token(path)
    rejected = [
        token for token in FORBIDDEN_COVERAGE_PATH_TOKENS if token in normalized
    ]
    if rejected:
        raise AltairValidationError(
            "coverage/callability must use the full Altair RR BED; rejected "
            f"{path!r} because it contains {','.join(rejected)}"
        )


def normalize_boundary_rows(path: Path | None) -> list[dict[str, str]]:
    if path is None:
        return []
    rows = []
    for row in _read_tsv(path):
        item = _select_fields(row, BOUNDARY_FIELDS)
        outside = _safe_int(item["calls_outside_rr"])
        gt50 = _safe_int(item["released_indels_gt50"])
        item["status"] = _status_value(item["status"])
        if outside > 0 or gt50 > 0:
            item["status"] = "FAIL"
            if outside > 0:
                item["reason"] = _append_reason(
                    item["reason"], "released_calls_outside_rr"
                )
            if gt50 > 0:
                item["reason"] = _append_reason(item["reason"], "released_indels_gt50")
        rows.append(item)
    return sorted(rows, key=lambda row: (row["sample_id"], row["released_vcf"]))


def collect_reasons(
    *,
    rr_rows: list[dict[str, str]],
    bar_rows: list[dict[str, str]],
    accuracy_rows: list[dict[str, str]],
    pooled_rows: list[dict[str, str]],
    coverage_rows: list[dict[str, str]],
    boundary_rows: list[dict[str, str]],
    invalid_denominators: list[dict[str, str]],
    expected_samples: tuple[str, ...],
) -> list[dict[str, object]]:
    reasons: list[dict[str, object]] = []
    missing_bar_samples = [
        sample_id
        for sample_id in expected_samples
        if not _bar_ready_for_sample(bar_rows, sample_id)
    ]
    if missing_bar_samples:
        reasons.append(
            {
                "code": "missing_giab_bar_metrics",
                "severity": "HOLD",
                "sample_ids": missing_bar_samples,
                "expected_inputs": [
                    f"{sample_id}.Altair_RR_v1_x_GIAB_HC.bed"
                    for sample_id in missing_bar_samples
                ],
            }
        )
    missing_accuracy_samples = sorted(
        {
            row["sample_id"]
            for row in accuracy_rows
            if row["status"] != "PASS" and row["sample_id"] in expected_samples
        }
    )
    if missing_accuracy_samples:
        reasons.append(
            {
                "code": "missing_accuracy_metrics",
                "severity": "HOLD",
                "sample_ids": missing_accuracy_samples,
            }
        )
    if invalid_denominators:
        reasons.append(
            {
                "code": "invalid_accuracy_denominator",
                "severity": "FAIL",
                "details": invalid_denominators,
            }
        )
    _append_status_reasons(reasons, "rr_manifest", rr_rows)
    _append_status_reasons(reasons, "bar_manifest", bar_rows)
    _append_status_reasons(reasons, "accuracy_metrics_pooled", pooled_rows)
    if not coverage_rows:
        reasons.append(
            {
                "code": "missing_rr_coverage_callability",
                "severity": "HOLD",
                "detail": "Full Altair RR coverage/callability TSV was not provided.",
            }
        )
    else:
        _append_status_reasons(reasons, "rr_coverage_callability", coverage_rows)
    if not boundary_rows:
        reasons.append(
            {
                "code": "missing_rr_boundary_verification",
                "severity": "HOLD",
                "detail": "Released VCF boundary verification TSV was not provided.",
            }
        )
    else:
        _append_status_reasons(reasons, "rr_boundary_verification", boundary_rows)
    return reasons


def build_summary(
    *,
    rr_rows: list[dict[str, str]],
    bar_rows: list[dict[str, str]],
    accuracy_rows: list[dict[str, str]],
    pooled_rows: list[dict[str, str]],
    coverage_rows: list[dict[str, str]],
    boundary_rows: list[dict[str, str]],
    reasons: list[dict[str, object]],
    expected_samples: tuple[str, ...],
) -> dict[str, object]:
    severity_order = {"FAIL": 2, "HOLD": 1}
    max_severity = max(
        (severity_order.get(str(reason["severity"]), 0) for reason in reasons),
        default=0,
    )
    overall_status = (
        "FAIL" if max_severity == 2 else "HOLD" if max_severity == 1 else "PASS"
    )
    return {
        "overall_status": overall_status,
        "expected_giab_samples": list(expected_samples),
        "expected_rr_chromosomes": list(EXPECTED_RR_CHROMOSOMES),
        "artifact_files": list(OUTPUT_FILENAMES),
        "counts": {
            "rr_manifest_rows": len(rr_rows),
            "bar_manifest_rows": len(bar_rows),
            "accuracy_by_sample_rows": len(accuracy_rows),
            "accuracy_pooled_rows": len(pooled_rows),
            "rr_coverage_rows": len(coverage_rows),
            "boundary_rows": len(boundary_rows),
        },
        "observed_giab_samples": {
            "bar_manifest": sorted(
                {row["sample_id"] for row in bar_rows if row["sample_id"]}
            ),
            "accuracy_metrics": sorted(
                {row["sample_id"] for row in accuracy_rows if row["status"] == "PASS"}
            ),
        },
        "reasons": reasons,
    }


def build_coverage_row_from_mosdepth(
    *,
    sample_id: str,
    run_id: str,
    library_id: str,
    rr_bed_name: str,
    rr_bed_sha256: str,
    rr_total_bases: int,
    regions_bed_gz: Path,
    thresholds_bed_gz: Path,
    coverage_tool_version: str,
    callable_definition: str,
) -> dict[str, str]:
    validate_coverage_region_path(rr_bed_name)
    mean_depth, median_depth = _mosdepth_region_depths(regions_bed_gz)
    bases_ge_10, bases_ge_20 = _mosdepth_threshold_bases(thresholds_bed_gz)
    denominator = rr_total_bases if rr_total_bases > 0 else 0
    return {
        "sample_id": sample_id,
        "run_id": run_id,
        "library_id": library_id,
        "rr_bed_name": rr_bed_name,
        "rr_bed_sha256": rr_bed_sha256,
        "rr_total_bases": str(rr_total_bases),
        "median_rr_depth": _format_float(median_depth),
        "mean_rr_depth": _format_float(mean_depth),
        "pct_rr_bases_ge_10x": _ratio(bases_ge_10, denominator),
        "pct_rr_bases_ge_20x": _ratio(bases_ge_20, denominator),
        "callable_fraction": _ratio(bases_ge_20, denominator),
        "callable_definition": callable_definition,
        "coverage_tool": "mosdepth",
        "coverage_tool_version": coverage_tool_version,
        "status": "PASS" if denominator > 0 else "HOLD",
        "reason": "" if denominator > 0 else "missing_rr_total_bases",
    }


def merge_coverage_tsvs(paths: list[Path], output: Path) -> None:
    rows = []
    for path in paths:
        rows.extend(normalize_coverage_rows(path))
    _write_tsv(output, COVERAGE_FIELDS, rows)


def build_boundary_rows_from_vcfs(
    *,
    vcf_paths: list[Path],
    rr_bed: Path,
    rr_bed_name: str,
    rr_bed_sha256: str,
    output: Path,
) -> None:
    intervals = load_bed_intervals(rr_bed)
    rows = []
    for vcf_path in vcf_paths:
        total = 0
        outside = 0
        gt50 = 0
        for record in iter_vcf_records(vcf_path):
            total += 1
            if not record_overlaps_intervals(
                record["chrom"], int(record["pos"]), intervals
            ):
                outside += 1
            if indel_length(record["ref"], record["alts"]) > 50:
                gt50 += 1
        sample_id = sample_id_from_vcf_name(vcf_path)
        status = "PASS" if outside == 0 and gt50 == 0 else "FAIL"
        reason = []
        if outside:
            reason.append("released_calls_outside_rr")
        if gt50:
            reason.append("released_indels_gt50")
        rows.append(
            {
                "sample_id": sample_id,
                "released_vcf": str(vcf_path),
                "rr_bed_name": rr_bed_name,
                "rr_bed_sha256": rr_bed_sha256,
                "total_released_calls": str(total),
                "calls_outside_rr": str(outside),
                "released_indels_gt50": str(gt50),
                "status": status,
                "reason": ";".join(reason),
            }
        )
    _write_tsv(output, BOUNDARY_FIELDS, sorted(rows, key=lambda row: row["sample_id"]))


def render_report_docx(
    *,
    template_docx: Path,
    output_docx: Path,
    summary: dict[str, object],
    rr_rows: list[dict[str, str]] | None = None,
    coverage_rows: list[dict[str, str]] | None = None,
    boundary_rows: list[dict[str, str]] | None = None,
) -> None:
    if not template_docx.is_file():
        raise AltairValidationError(f"Report template DOCX not found: {template_docx}")
    output_docx.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(template_docx, output_docx)
    rr_row = (rr_rows or [{}])[0]
    coverage = coverage_rows or []
    boundary = boundary_rows or []
    replacements = {token: "NA" for token in _docx_tokens(template_docx)}
    replacements.update(
        {
            "WORKFLOW_COMPLETION_STATUS": str(summary["overall_status"]),
            "FINAL_DISPOSITION_RATIONALE": "; ".join(
                str(reason["code"]) for reason in summary.get("reasons", [])
            )
            or "All Altair validation package gates passed.",
            "RR_BED_NAME": rr_row.get("rr_bed_name", "NA"),
            "RR_BED_SHA256": rr_row.get("rr_bed_sha256", "NA"),
            "RR_BED_ROW_COUNT": rr_row.get("rr_row_count", "NA"),
            "RR_BED_TOTAL_BASES": rr_row.get("rr_total_bases", "NA"),
            "RR_TOTAL_BASES": rr_row.get("rr_total_bases", "NA"),
            "RR_EXPECTED_ROW_COUNT": rr_row.get("rr_row_count", "NA"),
            "RR_EXPECTED_TOTAL_BASES": rr_row.get("rr_total_bases", "NA"),
            "RR_CHROMOSOME_SET": rr_row.get("observed_chromosomes", "NA"),
            "RR_BASES_GE10X_PCT": _coverage_average(coverage, "pct_rr_bases_ge_10x"),
            "RR_BASES_GE20X_PCT": _coverage_average(coverage, "pct_rr_bases_ge_20x"),
            "RR_CALLABLE_FRACTION": _coverage_average(coverage, "callable_fraction"),
            "MEDIAN_RR_DEPTH": _coverage_average(coverage, "median_rr_depth"),
            "AUTOSOME_RR_BASES": rr_row.get("rr_total_bases", "NA"),
            "AUTOSOME_GE10X_PCT": _coverage_average(coverage, "pct_rr_bases_ge_10x"),
            "AUTOSOME_GE20X_PCT": _coverage_average(coverage, "pct_rr_bases_ge_20x"),
            "AUTOSOME_CALLABLE_FRACTION": _coverage_average(
                coverage, "callable_fraction"
            ),
            "AUTOSOME_MEDIAN_DEPTH": _coverage_average(coverage, "median_rr_depth"),
            "CALLS_OUTSIDE_RR_COUNT": _boundary_sum(boundary, "calls_outside_rr"),
            "INDEL_GT50_RELEASED_COUNT": _boundary_sum(
                boundary, "released_indels_gt50"
            ),
            "QC_REPORT_FILENAME": output_docx.name,
            "PIPELINE_NAME": "daylily-omics-analysis",
            "PIPELINE_WORKFLOW_ID": "produce_altair_validation_artifacts",
            "METRIC_NAME_1": "Overall status",
            "VALUE_1": str(summary["overall_status"]),
            "THRESHOLD_1": "PASS requires all required evidence and gates",
            "UNIT_1": "status",
            "SOURCE_1": "validation_summary.json",
            "METRIC_NAME_2": "Expected GIAB samples",
            "VALUE_2": ",".join(summary["expected_giab_samples"]),
            "THRESHOLD_2": "HG001-HG007 present",
            "UNIT_2": "sample IDs",
            "SOURCE_2": "bar_manifest.tsv",
            "METRIC_NAME_3": "RR chromosome policy",
            "VALUE_3": ",".join(summary["expected_rr_chromosomes"]),
            "THRESHOLD_3": "chr1-chr22,chrX unless approved otherwise",
            "UNIT_3": "chromosomes",
            "SOURCE_3": "rr_manifest.tsv",
            "METRIC_NAME_4": "Accuracy denominator",
            "VALUE_4": "sample-specific BAR",
            "THRESHOLD_4": "Altair_RR_v1 intersect GIAB_HC(sample)",
            "UNIT_4": "BED",
            "SOURCE_4": "accuracy_metrics_by_sample.tsv",
            "METRIC_NAME_5": "Coverage denominator",
            "VALUE_5": "full Altair_RR_v1",
            "THRESHOLD_5": "not BAR, GIAB HC, WGS, or core BED",
            "UNIT_5": "BED",
            "SOURCE_5": "rr_coverage_callability_by_sample.tsv",
            "machine_readable_tokens": "Filled from validation_summary.json and validation_artifacts TSVs.",
        }
    )
    replacements.update(
        {
            "ALTAIR_OVERALL_STATUS": str(summary["overall_status"]),
            "ALTAIR_STATUS_REASONS": "; ".join(
                str(reason["code"]) for reason in summary.get("reasons", [])
            )
            or "None",
            "ALTAIR_EXPECTED_GIAB_SAMPLES": ",".join(summary["expected_giab_samples"]),
            "ALTAIR_EXPECTED_RR_CHROMOSOMES": ",".join(
                summary["expected_rr_chromosomes"]
            ),
        }
    )
    _replace_docx_tokens(output_docx, replacements)


def _docx_tokens(path: Path) -> set[str]:
    tokens = set()
    token_pattern = re.compile(r"\{\{([^{}]+)\}\}")
    with zipfile.ZipFile(path, "r") as docx:
        for name in docx.namelist():
            if name.startswith("word/") and name.endswith(".xml"):
                text = docx.read(name).decode("utf-8", errors="ignore")
                tokens.update(token_pattern.findall(text))
    return tokens


def _coverage_average(rows: list[dict[str, str]], field: str) -> str:
    values = []
    for row in rows:
        value = row.get(field, "")
        if value not in {"", "NA", "None"}:
            values.append(float(value))
    if not values:
        return "NA"
    return _format_float(sum(values) / len(values))


def _boundary_sum(rows: list[dict[str, str]], field: str) -> str:
    if not rows:
        return "NA"
    return str(sum(_safe_int(row.get(field, "")) for row in rows))


def _legacy_report_tokens(summary: dict[str, object]) -> dict[str, str]:
    return {
        "ALTAIR_OVERALL_STATUS": str(summary["overall_status"]),
        "ALTAIR_STATUS_REASONS": "; ".join(
            str(reason["code"]) for reason in summary.get("reasons", [])
        )
        or "None",
        "ALTAIR_EXPECTED_GIAB_SAMPLES": ",".join(summary["expected_giab_samples"]),
        "ALTAIR_EXPECTED_RR_CHROMOSOMES": ",".join(summary["expected_rr_chromosomes"]),
    }


def load_bed_intervals(path: Path) -> dict[str, list[tuple[int, int]]]:
    intervals: dict[str, list[tuple[int, int]]] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            chrom, start, end, *_rest = line.rstrip("\n").split("\t")
            intervals.setdefault(chrom, []).append((int(start), int(end)))
    return {chrom: sorted(values) for chrom, values in intervals.items()}


def record_overlaps_intervals(
    chrom: str,
    one_based_pos: int,
    intervals: dict[str, list[tuple[int, int]]],
) -> bool:
    zero_based = one_based_pos - 1
    for start, end in intervals.get(chrom, []):
        if zero_based < start:
            return False
        if start <= zero_based < end:
            return True
    return False


def iter_vcf_records(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 5:
                continue
            yield {
                "chrom": fields[0],
                "pos": fields[1],
                "ref": fields[3],
                "alts": fields[4].split(","),
            }


def indel_length(ref: str, alts: list[str]) -> int:
    return max((abs(len(alt) - len(ref)) for alt in alts if alt != "."), default=0)


def sample_id_from_vcf_name(path: Path) -> str:
    match = re.search(r"(HG00[1-7])", path.name)
    return match.group(1) if match else path.name.split(".")[0]


def bed_chromosomes(path: Path) -> list[str]:
    observed = set()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            observed.add(line.split("\t", 1)[0])
    return _ordered_chroms(observed)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_many_tsv(paths: tuple[Path, ...]) -> list[dict[str, str]]:
    rows = []
    for path in paths:
        rows.extend(_read_tsv(path))
    return rows


def _read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise AltairValidationError(f"Missing input TSV: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames is None:
            raise AltairValidationError(f"TSV has no header: {path}")
        return [
            {str(key): str(value or "").strip() for key, value in row.items()}
            for row in reader
        ]


def _write_tsv(
    path: Path, fieldnames: tuple[str, ...], rows: list[dict[str, str]]
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            delimiter="\t",
            fieldnames=fieldnames,
            lineterminator="\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def _select_fields(row: dict[str, str], fields: tuple[str, ...]) -> dict[str, str]:
    return {field: _first_value(row, field) for field in fields}


def _first_value(row: dict[str, str], field: str) -> str:
    aliases = {
        "sample_id": ("sample_id", "AltId", "alt_id", "GIAB_ID", "sample", "Sample"),
        "variant_class": ("variant_class", "VariantClass", "class"),
        "status": ("status", "Status", "PASS", "pass"),
    }
    for key in aliases.get(field, (field,)):
        if key in row and str(row[key]).strip():
            return str(row[key]).strip()
    return ""


def _sample_id(row: dict[str, str]) -> str:
    return _first_alias(
        row, ("sample_id", "AltId", "alt_id", "GIAB_ID", "sample", "Sample")
    )


def _variant_class(row: dict[str, str]) -> str:
    return _first_alias(row, ("VariantClass", "variant_class", "class"))


def _denominator(row: dict[str, str]) -> str:
    return _first_alias(
        row,
        (
            "accuracy_denominator",
            "denominator_bed_name",
            "denominator",
            "ROI",
            "roi",
            "bar_bed_name",
            "region",
        ),
    )


def _first_alias(row: dict[str, str], keys: tuple[str, ...]) -> str:
    for key in keys:
        if key in row and str(row[key]).strip():
            return str(row[key]).strip()
    return ""


def _status_value(raw: str) -> str:
    value = str(raw or "").strip().upper()
    if value in {"", "TRUE", "YES", "1", "PASS", "PASSED", "OK"}:
        return "PASS"
    if value.startswith("HOLD"):
        return "HOLD"
    return "FAIL"


def _claim_class(variant_class: str) -> str | None:
    for claim_class, source_classes in ACCURACY_GROUPS.items():
        if variant_class in source_classes:
            return claim_class
    return None


def _allowed_denominators(bar_rows: list[dict[str, str]]) -> dict[str, set[str]]:
    allowed: dict[str, set[str]] = {}
    for row in bar_rows:
        sample_id = row["sample_id"]
        if row["status"] != "PASS" or not _is_sample_specific_bar(row):
            continue
        tokens = {
            row["bar_bed_name"],
            Path(row["bar_bed_name"]).name,
            Path(row["bar_bed_name"]).stem,
        }
        allowed[sample_id] = {_normalize_token(token) for token in tokens if token}
    return allowed


def _primary_bar_name(bar_rows: list[dict[str, str]], sample_id: str) -> str:
    for row in bar_rows:
        if row["sample_id"] == sample_id:
            return row["bar_bed_name"]
    return f"{sample_id}.Altair_RR_v1_x_GIAB_HC.bed"


def _primary_bar_sha(bar_rows: list[dict[str, str]], sample_id: str) -> str:
    for row in bar_rows:
        if row["sample_id"] == sample_id:
            return row["bar_bed_sha256"]
    return ""


def _bar_ready_for_sample(bar_rows: list[dict[str, str]], sample_id: str) -> bool:
    return any(
        row["sample_id"] == sample_id
        and row["status"] == "PASS"
        and _is_sample_specific_bar(row)
        and _is_present(row["bar_bed_sha256"])
        for row in bar_rows
    )


def _is_sample_specific_bar(row: dict[str, str]) -> bool:
    expected = f"{row['sample_id']}.Altair_RR_v1_x_GIAB_HC.bed"
    return row["bar_bed_name"] == expected


def _append_status_reasons(
    reasons: list[dict[str, object]],
    source: str,
    rows: list[dict[str, str]],
) -> None:
    for row in rows:
        status = row.get("status", "PASS")
        if status == "PASS":
            continue
        reasons.append(
            {
                "code": source + "_status",
                "severity": "HOLD" if status == "HOLD" else "FAIL",
                "status": status,
                "sample_id": row.get("sample_id", ""),
                "reason": row.get("reason", ""),
            }
        )


def _row_label(row: dict[str, str]) -> str:
    return _first_alias(row, ("mqc_id", "id", "source_row", "ROI"))


def _int(row: dict[str, str], key: str) -> int:
    return _safe_int(_first_alias(row, (key, key.lower())))


def _safe_int(value: str) -> int:
    if value in {"", "NA", "None", None}:
        return 0
    return int(float(str(value)))


def _ratio(numerator: int | float, denominator: int | float) -> str:
    if denominator == 0:
        return ""
    return _format_float(float(numerator) / float(denominator))


def _format_float(value: float) -> str:
    if not math.isfinite(value):
        return ""
    return f"{value:.12g}"


def _normalize_token(value: str) -> str:
    return (
        str(value or "")
        .strip()
        .lower()
        .replace("\\", "/")
        .replace("/", "_")
        .replace(".", "_")
        .replace("-", "_")
    )


def _is_present(value: str) -> bool:
    return str(value or "").strip() not in {"", "NA", "None", "null"}


def _append_reason(current: str, reason: str) -> str:
    if not current:
        return reason
    if reason in current.split(";"):
        return current
    return current + ";" + reason


def _chrom_list(value: str) -> list[str]:
    if not _is_present(value):
        return []
    return [
        item.strip()
        for item in value.split(",")
        if item.strip() and item.strip() != "NA"
    ]


def _join(values: list[str] | tuple[str, ...]) -> str:
    return ",".join(values) if values else "NA"


def _ordered_chroms(values: set[str]) -> list[str]:
    expected = [chrom for chrom in EXPECTED_RR_CHROMOSOMES if chrom in values]
    extras = sorted(values - set(EXPECTED_RR_CHROMOSOMES))
    return expected + extras


def _mosdepth_region_depths(regions_bed_gz: Path) -> tuple[float, float]:
    weighted_sum = 0.0
    total_bases = 0
    depth_values: list[tuple[float, int]] = []
    with gzip.open(regions_bed_gz, "rt", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            chrom, start, end, *_middle, depth = line.rstrip("\n").split("\t")
            del chrom, _middle
            bases = int(end) - int(start)
            value = float(depth)
            weighted_sum += value * bases
            total_bases += bases
            depth_values.append((value, bases))
    mean_depth = weighted_sum / total_bases if total_bases else 0.0
    return mean_depth, _weighted_median(depth_values)


def _weighted_median(values: list[tuple[float, int]]) -> float:
    if not values:
        return 0.0
    total = sum(weight for _value, weight in values)
    midpoint = total / 2
    running = 0
    for value, weight in sorted(values):
        running += weight
        if running >= midpoint:
            return value
    return values[-1][0]


def _mosdepth_threshold_bases(thresholds_bed_gz: Path) -> tuple[int, int]:
    bases_ge_10 = 0
    bases_ge_20 = 0
    header: list[str] | None = None
    with gzip.open(thresholds_bed_gz, "rt", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if fields[0].startswith("#"):
                header = [field.lstrip("#") for field in fields]
                continue
            if header and "10X" in header and "20X" in header:
                bases_ge_10 += int(fields[header.index("10X")])
                bases_ge_20 += int(fields[header.index("20X")])
            else:
                bases_ge_10 += int(fields[-3])
                bases_ge_20 += int(fields[-2])
    return bases_ge_10, bases_ge_20


def _replace_docx_tokens(path: Path, replacements: dict[str, str]) -> None:
    tmp_path = path.with_suffix(".tmp.docx")
    with zipfile.ZipFile(path, "r") as src, zipfile.ZipFile(tmp_path, "w") as dst:
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename.startswith("word/") and item.filename.endswith(".xml"):
                text = data.decode("utf-8")
                for key, value in replacements.items():
                    text = text.replace("{{" + key + "}}", escape(value))
                data = text.encode("utf-8")
            dst.writestr(item, data)
    tmp_path.replace(path)
