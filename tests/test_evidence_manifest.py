from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

import pytest

from daylily_omics_analysis.evidence_manifest import (
    EvidenceManifestError,
    EvidenceMetadata,
    build_multiqc_final_evidence_manifest,
    canonical_json_bytes,
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


def _metadata() -> EvidenceMetadata:
    return EvidenceMetadata(
        analysis_name="analysis-1",
        run_name="run-1",
        genome_build="hg38",
        pipeline_name="daylily-omics-analysis",
        pipeline_version="1.0.0",
        git_sha="abc123",
        snakemake_version="7.32.4",
        workflow_config_hash="cfg123",
        workflow_profile="local",
        provenance_refs={
            "pipeline_details_md": "pipeline_details.md",
            "planned_workflow_mmd": "pipeline_workflow_planned.mmd",
        },
    )


def test_multiqc_evidence_manifest_is_deterministic_and_local_only(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    outputs = tmp_path / "results/day/hg38/reports"

    manifest = build_multiqc_final_evidence_manifest(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"], paths["benchmark"]],
        output_manifest=outputs / "dayoa_evidence_manifest.json",
        metadata=_metadata(),
        generated_at=FIXED_TIME,
    )

    manifest2 = build_multiqc_final_evidence_manifest(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["benchmark"], paths["custom"]],
        output_manifest=outputs / "again.manifest.json",
        metadata=_metadata(),
        generated_at=FIXED_TIME,
    )

    assert canonical_json_bytes(manifest) == canonical_json_bytes(manifest2)
    assert manifest["schema_version"] == "dayoa.evidence_manifest.v1"
    assert manifest["manifest_checksum"] == manifest_checksum(manifest)
    assert manifest["producer"]["registration_side_effects"] is False
    assert "storage_uri" not in json.dumps(manifest)
    assert "dewey" not in json.dumps(manifest).lower()
    assert "qeo" not in json.dumps(manifest).lower()


def test_multiqc_evidence_manifest_classifies_key_files_and_preserves_unknowns(
    tmp_path: Path,
) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    manifest = build_multiqc_final_evidence_manifest(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"], paths["benchmark"]],
        output_manifest=tmp_path / "manifest.json",
        metadata=_metadata(),
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


def test_required_multiqc_files_fail_loudly(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    (paths["data_dir"] / "multiqc_sources.txt").unlink()

    with pytest.raises(EvidenceManifestError, match="Required evidence file"):
        build_multiqc_final_evidence_manifest(
            analysis_root=tmp_path,
            html_path=paths["html"],
            multiqc_data_dir=paths["data_dir"],
            stage_manifest=paths["stage_manifest"],
            parser_relevant_paths=[paths["custom"]],
            output_manifest=tmp_path / "manifest.json",
            metadata=_metadata(),
            generated_at=FIXED_TIME,
        )


def test_sample_collision_warnings_are_preserved(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    manifest = build_multiqc_final_evidence_manifest(
        analysis_root=tmp_path,
        html_path=paths["html"],
        multiqc_data_dir=paths["data_dir"],
        stage_manifest=paths["stage_manifest"],
        parser_relevant_paths=[paths["custom"]],
        output_manifest=tmp_path / "manifest.json",
        metadata=_metadata(),
        generated_at=FIXED_TIME,
    )

    warning_types = {warning["warning_type"] for warning in manifest["warnings"]}
    assert "sample_name_collision" in warning_types
    assert "sample_base_collision" in warning_types


def test_cli_writes_local_evidence_manifest(tmp_path: Path) -> None:
    paths = _make_multiqc_fixture(tmp_path)
    rc = main(
        [
            "multiqc-final",
            "--analysis-root",
            str(tmp_path),
            "--analysis-name",
            "analysis-1",
            "--run-name",
            "run-1",
            "--genome-build",
            "hg38",
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
            "--evidence-manifest-output",
            str(tmp_path / "manifest.json"),
            "--generated-at",
            FIXED_TIME,
        ]
    )

    assert rc == 0
    assert json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))[
        "schema_version"
    ] == "dayoa.evidence_manifest.v1"


def test_active_dayoa_tree_has_no_registration_surfaces() -> None:
    result = subprocess.run(
        [
            "git",
            "ls-files",
            "--",
            ".",
            ":(exclude)quarantine/**",
            ":(exclude)resources/**",
            ":(exclude)docs/plans/**",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    active_paths = [
        Path(path)
        for path in result.stdout.splitlines()
        if path not in {"tests/test_evidence_manifest.py", "tests/test_multiqc_qc_targets.py"}
    ]
    haystack = "\n".join(
        f"{path}: {path.read_text(encoding='utf-8', errors='ignore')}"
        for path in active_paths
        if path.is_file()
    ).lower()

    for forbidden in (
        "qeo_registration",
        "register_qeo_artifacts",
        "produce_qeo_",
        "dewey_receipt",
        "qeo_manifest",
        "qeo_ingest_manifest",
        "publish_qeo_ingest_event",
    ):
        assert forbidden not in haystack, forbidden
