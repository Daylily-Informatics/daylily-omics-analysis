from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def test_snakefile_imports_altair_validation_rules() -> None:
    snakefile = _read("workflow/Snakefile")

    assert 'include: "rules/altair_validation.smk"' in snakefile


def test_altair_validation_target_writes_required_artifacts() -> None:
    rules = _read("workflow/rules/altair_validation.smk")

    assert "rule produce_altair_validation_artifacts:" in rules
    for expected in (
        "validation_summary.json",
        "rr_manifest.tsv",
        "bar_manifest.tsv",
        "accuracy_metrics_by_sample.tsv",
        "accuracy_metrics_pooled.tsv",
        "rr_coverage_callability_by_sample.tsv",
        "rr_boundary_verification.tsv",
    ):
        assert expected in rules
    assert "python -m daylily_omics_analysis.altair_validation build" in rules


def test_rr_coverage_uses_full_rr_bed_and_rejects_non_rr_paths() -> None:
    rules = _read("workflow/rules/altair_validation.smk")

    assert "rule altair_rr_mosdepth:" in rules
    assert 'config.get("altair_validation", {})' not in rules
    assert 'get("output_dir", "validation_artifacts")' not in rules
    assert '_altair_coverage_param("min_mapq")' in rules
    assert '_altair_coverage_param("depth_bins")' in rules
    assert "--by {input.full_rr_bed:q}" in rules
    assert "Altair_RR_v1.regions.bed.gz" in rules
    assert "coverage-from-mosdepth" in rules
    for rejected in (
        "altair_rr_v1_x_giab",
        "giabhc",
        "giab_hc",
        "clinvar",
        "wgs",
        "core",
        "whole_genome",
    ):
        assert f'"{rejected}"' in rules


def test_boundary_verification_is_distinct_from_accuracy_benchmarking() -> None:
    rules = _read("workflow/rules/altair_validation.smk")
    cli = _read("daylily_omics_analysis/altair_validation/cli.py")

    assert "rule altair_rr_boundary_verification:" in rules
    assert "boundary-from-vcf" in rules
    assert "released_indels_gt50" not in rules
    assert "altair_validation.boundary.released_vcfs" in rules
    assert 'coverage.add_argument("--rr-bed-sha256", required=True)' in cli
    assert 'boundary.add_argument("--rr-bed-sha256", required=True)' in cli
    assert 'default="mosdepth DP>=20x over full Altair_RR_v1"' not in cli


def test_profile_templates_declare_altair_validation_inputs() -> None:
    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        cfg = _yaml(path)["altair_validation"]
        assert cfg["rr_manifest"] == ""
        assert cfg["bar_manifest"] == ""
        assert cfg["giab_concordance"] == ""
        assert cfg["boundary_verification"] == ""
        assert cfg["report_template_docx"] == ""
        assert cfg["coverage"]["full_rr_bed"] == ""
        assert cfg["coverage"]["callable_definition"] == (
            "mosdepth DP>=20x over full Altair_RR_v1"
        )
        assert cfg["boundary"]["released_vcfs"] == []
        assert cfg["output_dir"] == "validation_artifacts"
