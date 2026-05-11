from __future__ import annotations

import csv
import json
from pathlib import Path

import pytest

from daylily_omics_analysis.altair_validation import (
    EXPECTED_GIAB_IDS,
    EXPECTED_RR_CHROMOSOMES,
    AltairValidationError,
    AltairValidationInputs,
    build_validation_artifacts,
    validate_coverage_region_path,
)


def _write_tsv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return path


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def _valid_rr_manifest(tmp_path: Path) -> Path:
    return _write_tsv(
        tmp_path / "rr_manifest.tsv",
        [
            {
                "rr_bed_name": "Altair_RR_v1.bed",
                "rr_bed_path": "/controlled/Altair_RR_v1.bed",
                "rr_bed_sha256": "rrsha",
                "rr_row_count": "2",
                "rr_total_bases": "1000",
                "genome_build": "hg38",
                "expected_chromosomes": ",".join(EXPECTED_RR_CHROMOSOMES),
                "observed_chromosomes": ",".join(EXPECTED_RR_CHROMOSOMES),
                "missing_chromosomes": "NA",
                "extra_chromosomes": "NA",
                "source_artifact": "approved_source",
                "approval_record": "approved_record",
                "status": "PASS",
                "reason": "",
            }
        ],
        [
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
        ],
    )


def _valid_bar_manifest(
    tmp_path: Path, samples: tuple[str, ...] = EXPECTED_GIAB_IDS
) -> Path:
    rows = []
    for sample_id in samples:
        rows.append(
            {
                "sample_id": sample_id,
                "rr_bed_name": "Altair_RR_v1.bed",
                "rr_bed_sha256": "rrsha",
                "giab_hc_bed_name": f"{sample_id}.GIAB_HC.bed",
                "giab_hc_bed_sha256": f"{sample_id.lower()}hcsha",
                "bar_bed_name": f"{sample_id}.Altair_RR_v1_x_GIAB_HC.bed",
                "bar_bed_sha256": f"{sample_id.lower()}barsha",
                "bar_row_count": "1",
                "bar_total_bases": "900",
                "chromosome_set": ",".join(EXPECTED_RR_CHROMOSOMES),
                "status": "PASS",
                "reason": "",
            }
        )
    return _write_tsv(
        tmp_path / "bar_manifest.tsv",
        rows,
        [
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
        ],
    )


def _concordance(
    tmp_path: Path,
    samples: tuple[str, ...] = EXPECTED_GIAB_IDS,
    *,
    denominator: str | None = None,
) -> Path:
    rows = []
    for sample_id in samples:
        denom = denominator or f"{sample_id}.Altair_RR_v1_x_GIAB_HC.bed"
        for variant_class, tp, fp, fn in (
            ("SNPts", "10", "1", "2"),
            ("SNPtv", "5", "0", "1"),
            ("INS_50", "3", "1", "1"),
            ("DEL_50", "2", "0", "1"),
            ("Indel_50", "1", "0", "0"),
            ("INS_gt50", "999", "999", "999"),
        ):
            rows.append(
                {
                    "mqc_id": f"{sample_id}_{variant_class}",
                    "VariantClass": variant_class,
                    "Sample": sample_id,
                    "TP": tp,
                    "FP": fp,
                    "FN": fn,
                    "ROI": denom,
                }
            )
    return _write_tsv(
        tmp_path / "giab_concordance.tsv",
        rows,
        ["mqc_id", "VariantClass", "Sample", "TP", "FP", "FN", "ROI"],
    )


def _coverage(tmp_path: Path) -> Path:
    rows = []
    for sample_id in EXPECTED_GIAB_IDS:
        rows.append(
            {
                "sample_id": sample_id,
                "run_id": "run1",
                "library_id": "lib1",
                "rr_bed_name": "Altair_RR_v1.bed",
                "rr_bed_sha256": "rrsha",
                "rr_total_bases": "1000",
                "median_rr_depth": "31",
                "mean_rr_depth": "30.5",
                "pct_rr_bases_ge_10x": "1",
                "pct_rr_bases_ge_20x": "0.99",
                "callable_fraction": "0.99",
                "callable_definition": "mosdepth DP>=20x over full Altair_RR_v1",
                "coverage_tool": "mosdepth",
                "coverage_tool_version": "mosdepth_0.3.2",
                "status": "PASS",
                "reason": "",
            }
        )
    return _write_tsv(
        tmp_path / "coverage.tsv",
        rows,
        [
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
        ],
    )


def _boundary(tmp_path: Path, *, outside: str = "0", gt50: str = "0") -> Path:
    rows = []
    for sample_id in EXPECTED_GIAB_IDS:
        rows.append(
            {
                "sample_id": sample_id,
                "released_vcf": f"{sample_id}.release.vcf.gz",
                "rr_bed_name": "Altair_RR_v1.bed",
                "rr_bed_sha256": "rrsha",
                "total_released_calls": "10",
                "calls_outside_rr": outside,
                "released_indels_gt50": gt50,
                "status": "PASS",
                "reason": "",
            }
        )
    return _write_tsv(
        tmp_path / "boundary.tsv",
        rows,
        [
            "sample_id",
            "released_vcf",
            "rr_bed_name",
            "rr_bed_sha256",
            "total_released_calls",
            "calls_outside_rr",
            "released_indels_gt50",
            "status",
            "reason",
        ],
    )


def _build_valid(tmp_path: Path) -> Path:
    output_dir = tmp_path / "validation_artifacts"
    build_validation_artifacts(
        AltairValidationInputs(
            rr_manifest=_valid_rr_manifest(tmp_path),
            bar_manifest=_valid_bar_manifest(tmp_path),
            giab_concordance=(_concordance(tmp_path),),
            rr_coverage_callability=_coverage(tmp_path),
            boundary_verification=_boundary(tmp_path),
            output_dir=output_dir,
        )
    )
    return output_dir


def test_build_writes_required_validation_artifacts_and_all_giab_samples(
    tmp_path: Path,
) -> None:
    output_dir = _build_valid(tmp_path)

    for expected_name in (
        "rr_manifest.tsv",
        "bar_manifest.tsv",
        "accuracy_metrics_by_sample.tsv",
        "accuracy_metrics_pooled.tsv",
        "rr_coverage_callability_by_sample.tsv",
        "rr_boundary_verification.tsv",
        "validation_summary.json",
    ):
        assert (output_dir / expected_name).is_file()

    summary = json.loads((output_dir / "validation_summary.json").read_text())
    assert summary["overall_status"] == "PASS"
    assert summary["observed_giab_samples"]["accuracy_metrics"] == list(
        EXPECTED_GIAB_IDS
    )

    bar_rows = _read_tsv(output_dir / "bar_manifest.tsv")
    accuracy_rows = _read_tsv(output_dir / "accuracy_metrics_by_sample.tsv")
    assert {row["sample_id"] for row in bar_rows} == set(EXPECTED_GIAB_IDS)
    assert {row["sample_id"] for row in accuracy_rows} == set(EXPECTED_GIAB_IDS)
    assert any(row["sample_id"] == "HG003" for row in bar_rows)
    assert any(row["sample_id"] == "HG003" for row in accuracy_rows)


def test_accuracy_aggregates_snv_and_le50_indels_and_excludes_gt50(
    tmp_path: Path,
) -> None:
    output_dir = _build_valid(tmp_path)
    pooled = {
        row["variant_class"]: row
        for row in _read_tsv(output_dir / "accuracy_metrics_pooled.tsv")
    }

    assert pooled["SNV"]["tp"] == str(15 * len(EXPECTED_GIAB_IDS))
    assert pooled["SNV"]["fp"] == str(1 * len(EXPECTED_GIAB_IDS))
    assert pooled["SNV"]["fn"] == str(3 * len(EXPECTED_GIAB_IDS))
    assert pooled["small_indel_le50"]["tp"] == str(6 * len(EXPECTED_GIAB_IDS))
    assert pooled["small_indel_le50"]["fp"] == str(1 * len(EXPECTED_GIAB_IDS))
    assert pooled["small_indel_le50"]["fn"] == str(2 * len(EXPECTED_GIAB_IDS))
    assert "999" not in (output_dir / "accuracy_metrics_by_sample.tsv").read_text()


def test_missing_hg003_bar_metrics_hold_with_explicit_expected_input(
    tmp_path: Path,
) -> None:
    output_dir = tmp_path / "validation_artifacts"
    samples_without_hg003 = tuple(
        sample for sample in EXPECTED_GIAB_IDS if sample != "HG003"
    )
    build_validation_artifacts(
        AltairValidationInputs(
            rr_manifest=_valid_rr_manifest(tmp_path),
            bar_manifest=_valid_bar_manifest(tmp_path, samples_without_hg003),
            giab_concordance=(_concordance(tmp_path, samples_without_hg003),),
            rr_coverage_callability=_coverage(tmp_path),
            boundary_verification=_boundary(tmp_path),
            output_dir=output_dir,
        )
    )

    summary = json.loads((output_dir / "validation_summary.json").read_text())
    assert summary["overall_status"] == "HOLD"
    missing_reason = [
        reason
        for reason in summary["reasons"]
        if reason["code"] == "missing_giab_bar_metrics"
    ][0]
    assert missing_reason["sample_ids"] == ["HG003"]
    assert missing_reason["expected_inputs"] == ["HG003.Altair_RR_v1_x_GIAB_HC.bed"]

    hg003_rows = [
        row
        for row in _read_tsv(output_dir / "accuracy_metrics_by_sample.tsv")
        if row["sample_id"] == "HG003"
    ]
    assert {row["status"] for row in hg003_rows} == {"HOLD"}


@pytest.mark.parametrize(
    "denominator",
    [
        "clinvar_genes",
        "Altair_RR_v1",
        "global_giabHC_x_clinvar_genes_union.bed",
        "giabHC",
    ],
)
def test_invalid_accuracy_denominators_fail_package(
    tmp_path: Path, denominator: str
) -> None:
    output_dir = tmp_path / "validation_artifacts"
    build_validation_artifacts(
        AltairValidationInputs(
            rr_manifest=_valid_rr_manifest(tmp_path),
            bar_manifest=_valid_bar_manifest(tmp_path),
            giab_concordance=(_concordance(tmp_path, denominator=denominator),),
            rr_coverage_callability=_coverage(tmp_path),
            boundary_verification=_boundary(tmp_path),
            output_dir=output_dir,
        )
    )
    summary = json.loads((output_dir / "validation_summary.json").read_text())
    assert summary["overall_status"] == "FAIL"
    assert any(
        reason["code"] == "invalid_accuracy_denominator"
        for reason in summary["reasons"]
    )


@pytest.mark.parametrize(
    "coverage_path",
    [
        "/refs/HG003.Altair_RR_v1_x_GIAB_HC.bed",
        "/refs/giabHC/HG003.bed",
        "/refs/clinvar_genes.bed",
        "/refs/hg38_wgs_core.bed",
        "/refs/whole_genome.bed",
    ],
)
def test_coverage_region_guard_rejects_non_rr_denominators(coverage_path: str) -> None:
    with pytest.raises(AltairValidationError):
        validate_coverage_region_path(coverage_path)


def test_chrX_policy_is_asserted_in_rr_manifest(tmp_path: Path) -> None:
    output_dir = _build_valid(tmp_path)
    rows = _read_tsv(output_dir / "rr_manifest.tsv")

    assert rows[0]["expected_chromosomes"].split(",") == list(EXPECTED_RR_CHROMOSOMES)
    assert "chrX" in rows[0]["observed_chromosomes"].split(",")
    assert rows[0]["missing_chromosomes"] == "NA"


def test_boundary_failures_prevent_pass(tmp_path: Path) -> None:
    output_dir = tmp_path / "validation_artifacts"
    build_validation_artifacts(
        AltairValidationInputs(
            rr_manifest=_valid_rr_manifest(tmp_path),
            bar_manifest=_valid_bar_manifest(tmp_path),
            giab_concordance=(_concordance(tmp_path),),
            rr_coverage_callability=_coverage(tmp_path),
            boundary_verification=_boundary(tmp_path, outside="1", gt50="1"),
            output_dir=output_dir,
        )
    )

    summary = json.loads((output_dir / "validation_summary.json").read_text())
    assert summary["overall_status"] == "FAIL"
    boundary_rows = _read_tsv(output_dir / "rr_boundary_verification.tsv")
    assert {row["status"] for row in boundary_rows} == {"FAIL"}
