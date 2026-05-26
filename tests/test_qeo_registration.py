from __future__ import annotations

import csv
import json
from pathlib import Path

import pytest

from daylily_omics_analysis.qeo_registration import (
    QeoRegistrationError,
    RegistrationConfig,
    build_analysis_artifact_set_registration,
    build_artifact_produced_event,
    build_multiqc_final_registration,
    canonical_json_bytes,
    dewey_idempotency_key,
    main,
    manifest_checksum,
    sha256_file,
)


FIXED_TIME = "2026-05-26T18:30:00Z"


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def _make_multiqc_fixture(root: Path) -> dict[str, Path]:
    reports = root / "results/day/hg38/reports"
    data_dir = reports / "DAY_final_multiqc_data"
    staged = reports / "multiqc_inputs/final"
    other = root / "results/day/hg38/other_reports"
    html = _write(reports / "DAY_final_multiqc.html", "<html>multiqc</html>\n")
    _write(data_dir / "multiqc_data.json", '{"report": "dayoa"}\n')
    _write(data_dir / "multiqc_general_stats.txt", "Sample\treads\nHG002\t10\n")
    _write(data_dir / "multiqc_sources.txt", "fastqc\tHG002\tfile.txt\n")
    _write(data_dir / "multiqc.log", "multiqc log\n")
    _write(data_dir / "extra_unknown.dat", "preserve me\n")
    custom = _write(other / "alignstats_combo_mqc.tsv", "Sample\tmetric\nHG002\t1\n")
    benchmark = _write(other / "rules_benchmark_data_mqc.tsv", "Sample\trule\nHG002\talign\n")
    manifest = staged / "manifest.tsv"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    with manifest.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "Sample",
                "module",
                "stage",
                "base_sample",
                "aligner",
                "deduper",
                "caller",
                "input_kind",
                "source_path",
                "staged_path",
                "group_id",
            ],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerow(
            {
                "Sample": "HG002",
                "module": "alignstats",
                "stage": "alignment",
                "base_sample": "HG002",
                "aligner": "sent",
                "deduper": "dmd",
                "caller": "",
                "input_kind": "custom_mqc",
                "source_path": str(custom),
                "staged_path": "alignstats_combo_mqc.tsv",
                "group_id": "group-a",
            }
        )
        writer.writerow(
            {
                "Sample": "HG002",
                "module": "alignstats",
                "stage": "alignment",
                "base_sample": "HG003",
                "aligner": "sent",
                "deduper": "dmd",
                "caller": "",
                "input_kind": "custom_mqc",
                "source_path": str(custom),
                "staged_path": "alignstats_combo_mqc.tsv",
                "group_id": "group-b",
            }
        )
    return {
        "html": html,
        "data_dir": data_dir,
        "stage_manifest": manifest,
        "custom": custom,
        "benchmark": benchmark,
    }


def _metadata() -> dict[str, str]:
    return {
        "analysis_euid": "Z-ANL-QEO1",
        "run_euid": "Z-RUN-QEO1",
        "workset_euid": "Z-WRK-QEO1",
        "pipeline_name": "daylily-omics-analysis",
        "pipeline_version": "1.0.0",
        "git_sha": "abc123",
        "snakemake_version": "7.32.4",
        "workflow_config_hash": "cfg123",
        "workflow_profile": "local",
    }


def _local_config() -> RegistrationConfig:
    return RegistrationConfig(mode="local_only")


def test_multiqc_registration_is_deterministic_and_parser_ready(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    outputs = tmp_path / "results/day/hg38/reports"

    manifest, receipt, qeo = build_multiqc_final_registration(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"], paths["benchmark"]],
        output_manifest=outputs / "DAY_final_multiqc.artifact_manifest.json",
        output_receipt=outputs / "DAY_final_multiqc.dewey_receipt.json",
        output_qeo_manifest=outputs / "DAY_final_multiqc.qeo_manifest.json",
        metadata=_metadata(),
        registration_config=_local_config(),
        generated_at=FIXED_TIME,
    )

    manifest2, receipt2, qeo2 = build_multiqc_final_registration(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["benchmark"], paths["custom"]],
        output_manifest=outputs / "again.manifest.json",
        output_receipt=outputs / "again.receipt.json",
        output_qeo_manifest=outputs / "again.qeo.json",
        metadata=_metadata(),
        registration_config=_local_config(),
        generated_at=FIXED_TIME,
    )

    assert canonical_json_bytes(manifest) == canonical_json_bytes(manifest2)
    assert canonical_json_bytes(receipt) == canonical_json_bytes(receipt2)
    assert canonical_json_bytes(qeo) == canonical_json_bytes(qeo2)
    assert manifest["manifest_checksum"] == manifest_checksum(manifest)
    assert qeo["manifest_checksum"] == manifest_checksum(qeo)
    assert receipt["registration_status"] == "local_only"
    assert all(not artifact["artifact_ref"].startswith("Z-") for artifact in receipt["artifacts"])
    assert any(artifact["relative_path"] == "." for artifact in receipt["artifacts"])
    assert qeo["parser_family"] == "multiqc"
    assert qeo["artifact_set_refs"]


def test_multiqc_registration_classifies_key_files_and_preserves_unknowns(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    manifest, _, qeo = build_multiqc_final_registration(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"], paths["benchmark"]],
        output_manifest=tmp_path / "manifest.json",
        output_receipt=tmp_path / "receipt.json",
        output_qeo_manifest=tmp_path / "qeo.json",
        metadata=_metadata(),
        registration_config=_local_config(),
        generated_at=FIXED_TIME,
    )

    by_path = {record["relative_path"]: record for record in manifest["files"]}
    custom_rel = "results/day/hg38/other_reports/alignstats_combo_mqc.tsv"
    unknown_rel = "results/day/hg38/reports/DAY_final_multiqc_data/extra_unknown.dat"
    assert by_path[custom_rel]["classification"] == "custom_mqc_tsv"
    assert by_path[custom_rel]["parser_relevant"] is True
    assert by_path[custom_rel]["sha256"] == sha256_file(paths["custom"])
    assert by_path[unknown_rel]["classification"] == "unknown"
    assert by_path[unknown_rel]["parser_relevant"] is False
    assert unknown_rel not in {hint["relative_path"] for hint in qeo["parser_hints"]}


def test_required_multiqc_files_fail_loudly(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    (paths["data_dir"] / "multiqc_sources.txt").unlink()

    with pytest.raises(QeoRegistrationError, match="Required artifact file"):
        build_multiqc_final_registration(
            analysis_root=tmp_path,
            html_path=paths["html"],
            multiqc_data_dir=paths["data_dir"],
            stage_manifest=paths["stage_manifest"],
            parser_relevant_paths=[paths["custom"]],
            output_manifest=tmp_path / "manifest.json",
            output_receipt=tmp_path / "receipt.json",
            output_qeo_manifest=tmp_path / "qeo.json",
            metadata=_metadata(),
            registration_config=_local_config(),
            generated_at=FIXED_TIME,
        )


def test_sample_collision_warnings_are_preserved(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    manifest, _, _ = build_multiqc_final_registration(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"]],
        output_manifest=tmp_path / "manifest.json",
        output_receipt=tmp_path / "receipt.json",
        output_qeo_manifest=tmp_path / "qeo.json",
        metadata=_metadata(),
        registration_config=_local_config(),
        generated_at=FIXED_TIME,
    )

    warning_types = {warning["warning_type"] for warning in manifest["warnings"]}
    assert "sample_name_collision" in warning_types
    assert "sample_base_collision" in warning_types


def test_dewey_mode_requires_explicit_identity() -> None:
    with pytest.raises(QeoRegistrationError, match="Dewey registration mode requires"):
        RegistrationConfig(mode="dewey", dewey_url="https://dewey.example").validate()


def test_analysis_artifact_set_registers_all_declared_inputs(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    log = _write(tmp_path / "results/day/hg38/reports/logs/all__mqc_fin_a.log", "log\n")

    manifest, receipt, qeo = build_analysis_artifact_set_registration(
        analysis_root=tmp_path,
        input_paths=[paths["html"], paths["custom"], log],
        output_manifest=tmp_path / "analysis_manifest.json",
        output_receipt=tmp_path / "analysis_receipt.json",
        output_qeo_manifest=tmp_path / "analysis_qeo.json",
        metadata=_metadata(),
        registration_config=_local_config(),
        generated_at=FIXED_TIME,
    )

    assert manifest["manifest_kind"] == "dayoa.analysis_artifact_set"
    receipt_paths = {artifact["relative_path"] for artifact in receipt["artifacts"]}
    assert ". " not in receipt_paths
    assert "." in receipt_paths
    assert "results/day/hg38/reports/DAY_final_multiqc.html" in receipt_paths
    assert "results/day/hg38/other_reports/alignstats_combo_mqc.tsv" in receipt_paths
    assert "results/day/hg38/reports/logs/all__mqc_fin_a.log" in receipt_paths
    assert qeo["parser_family"] == "dayoa_analysis_artifact_set"


def test_idempotency_key_and_event_are_replay_safe(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    manifest, receipt, _ = build_multiqc_final_registration(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"]],
        output_manifest=tmp_path / "manifest.json",
        output_receipt=tmp_path / "receipt.json",
        output_qeo_manifest=tmp_path / "qeo.json",
        metadata=_metadata(),
        registration_config=_local_config(),
        generated_at=FIXED_TIME,
    )

    key1 = dewey_idempotency_key(
        producer_system="daylily-omics-analysis",
        artifact_type="dayoa.multiqc_html",
        identity=manifest["manifest_checksum"],
    )
    key2 = dewey_idempotency_key(
        producer_system="daylily-omics-analysis",
        artifact_type="dayoa.multiqc_html",
        identity=manifest["manifest_checksum"],
    )
    assert key1 == key2
    assert key1.startswith("dayoa:")

    event1 = build_artifact_produced_event(
        manifest=manifest,
        receipt=receipt,
        correlation_id=manifest["manifest_checksum"],
        occurred_at=FIXED_TIME,
    )
    event2 = build_artifact_produced_event(
        manifest=manifest,
        receipt=receipt,
        correlation_id=manifest["manifest_checksum"],
        occurred_at=FIXED_TIME,
    )
    assert event1 == event2
    assert event1["event_type"] == "lsmc.daylily.artifact.produced.v1"
    assert "Sample" not in json.dumps(event1)


def test_cli_local_only_multiqc_registration(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    rc = main(
        [
            "multiqc-final",
            "--analysis-root",
            str(tmp_path),
            "--mode",
            "local_only",
            "--analysis-euid",
            "Z-ANL-QEO1",
            "--run-euid",
            "Z-RUN-QEO1",
            "--pipeline-name",
            "daylily-omics-analysis",
            "--pipeline-version",
            "1.0.0",
            "--git-sha",
            "abc123",
            "--snakemake-version",
            "7.32.4",
            "--workflow-config-hash",
            "cfg123",
            "--workflow-profile",
            "local",
            "--html",
            str(paths["html"]),
            "--multiqc-data-dir",
            str(paths["data_dir"]),
            "--stage-manifest",
            str(paths["stage_manifest"]),
            "--parser-relevant",
            str(paths["custom"]),
            "--artifact-manifest-output",
            str(tmp_path / "manifest.json"),
            "--dewey-receipt-output",
            str(tmp_path / "receipt.json"),
            "--qeo-manifest-output",
            str(tmp_path / "qeo.json"),
            "--generated-at",
            FIXED_TIME,
        ]
    )

    assert rc == 0
    assert json.loads((tmp_path / "receipt.json").read_text(encoding="utf-8"))[
        "registration_status"
    ] == "local_only"
