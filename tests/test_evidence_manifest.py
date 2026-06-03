from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

import pytest

from daylily_omics_analysis.evidence_manifest import (
    EvidenceManifestError,
    EvidenceMetadata,
    build_analysis_evidence_manifest,
    build_multiqc_final_evidence_manifest,
    canonical_json_bytes,
    file_classification,
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
    final_html_rel = "results/day/hg38/reports/DAY_final_multiqc.html"
    custom_rel = "results/day/hg38/other_reports/alignstats_combo_mqc.tsv"
    data_extra_rel = "results/day/hg38/reports/DAY_final_multiqc_data/extra_unknown.dat"
    assert by_path[final_html_rel]["metadata"] == {
        "genome_build": "hg38",
        "report_kind": "final",
        "report_name": "DAY_final_multiqc",
        "result_scope": "day",
    }
    assert by_path[custom_rel]["classification"] == "custom_mqc_tsv"
    assert by_path[custom_rel]["parser_relevant"] is True
    assert by_path[custom_rel]["sha256"] == sha256_file(paths["custom"])
    assert by_path[data_extra_rel]["classification"] == "multiqc_data_artifact"
    assert by_path[data_extra_rel]["parser_relevant"] is False


def test_file_classification_covers_analysis_outputs_and_indexes() -> None:
    cases = {
        "results/day/hg38/HG002/calls/HG002.vcf": ("variant_vcf", False),
        "results/day/hg38/HG002/calls/HG002.vcf.gz": ("variant_vcf", False),
        "results/day/hg38/HG002/calls/HG002.vcf.gz.tbi": (
            "variant_vcf_index",
            False,
        ),
        "results/day/hg38/HG002/calls/HG002.vcf.gz.csi": (
            "variant_vcf_index",
            False,
        ),
        "results/day/hg38/HG002/align/HG002.cram": ("alignment_cram", False),
        "results/day/hg38/HG002/align/HG002.cram.crai": (
            "alignment_cram_index",
            False,
        ),
        "results/day/hg38/HG002/align/HG002.bam": ("alignment_bam", False),
        "results/day/hg38/HG002/align/HG002.bam.bai": (
            "alignment_bam_index",
            False,
        ),
        "results/day/hg38/HG002/align/HG002.bam.csi": (
            "alignment_bam_index",
            False,
        ),
        "results/runs/RUN1/run_qc/illumina/multiqc_report.html": (
            "multiqc_html",
            True,
        ),
        "results/runs/RUN1/bclconvert/multiqc_report_data/multiqc_bclconvert.txt": (
            "multiqc_data_text_artifact",
            True,
        ),
        "results/runs/RUN1/run_qc/illumina/summary.tsv": ("run_qc_tsv", True),
        "results/runs/RUN1/bclconvert/metrics/rollup.json": (
            "bclconvert_json",
            True,
        ),
    }

    for relative_path, expected in cases.items():
        assert file_classification(relative_path) == expected


def test_analysis_inventory_discovers_results_multiqc_and_derivable_metadata(
    tmp_path: Path,
) -> None:
    _make_multiqc_fixture(tmp_path)
    _write(tmp_path / "config/samples.tsv", "SAMPLEID\nHG002\nHG003\n")
    _write(
        tmp_path / "config/units.tsv",
        (
            "SAMPLEID\tRUNID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\n"
            "HG002\tRUN42\tEXP1\t1\tBC01\tPCR-free\tLSMC\tNOVASEQ\n"
            "HG003\tRUN42\tEXP2\t2\tBC02\tPCR-free\tLSMC\tNOVASEQ\n"
        ),
    )
    _write(
        tmp_path / "results/day/hg38/HG002/align/HG002.sent.cram",
        "cram bytes\n",
    )
    _write(
        tmp_path / "results/day/hg38/HG002/align/HG002.sent.cram.crai",
        "cram index\n",
    )
    _write(tmp_path / "results/day/hg38/HG002/align/HG002.sent.bam", "bam bytes\n")
    _write(
        tmp_path / "results/day/hg38/HG002/align/HG002.sent.bam.bai",
        "bam index\n",
    )
    _write(tmp_path / "results/day/hg38/HG002/variants/HG002.snv.vcf.gz", "vcf\n")
    _write(
        tmp_path / "results/day/hg38/HG002/variants/HG002.snv.vcf.gz.tbi",
        "vcf index\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/run_qc/illumina/multiqc_report.html",
        "<html>run qc</html>\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/run_qc/illumina/multiqc_report_data/multiqc_data.json",
        "{}\n",
    )
    _write(
        tmp_path
        / "results/runs/RUN42/run_qc/illumina/multiqc_report_data/multiqc_general_stats.txt",
        "Sample\tReads\nRUN42\t1\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/run_qc/illumina/illumina_run_qc.json",
        "{}\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/run_qc/illumina/summary.tsv",
        "Sample\tReads\nRUN42\t1\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/run_qc/illumina/logs/illumina_run_qc_multiqc.log",
        "log\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/bclconvert/multiqc_report.html",
        "<html>bcl</html>\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/bclconvert/multiqc_report_data/multiqc_data.json",
        "{}\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/bclconvert/multiqc_report_data/multiqc_bclconvert.txt",
        "Sample\tReads\nRUN42\t1\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/bclconvert/metrics/rollup.json",
        "{}\n",
    )
    _write(
        tmp_path / "results/runs/RUN42/bclconvert/multiqc_inputs/bclconvert_demux_mqc.tsv",
        "Sample\tReads\nRUN42\t1\n",
    )
    output = tmp_path / "results/day/hg38/reports/dayoa_evidence_manifest.json"

    manifest = build_analysis_evidence_manifest(
        analysis_root=tmp_path,
        output_manifest=output,
        metadata=_metadata(),
        generated_at=FIXED_TIME,
    )

    by_path = {record["relative_path"]: record for record in manifest["files"]}
    cram = by_path["results/day/hg38/HG002/align/HG002.sent.cram"]
    assert cram["classification"] == "alignment_cram"
    assert cram["metadata"] == {
        "artifact_format": "cram",
        "genome_build": "hg38",
        "result_scope": "day",
        "sample_id": "HG002",
    }
    assert (
        by_path["results/day/hg38/HG002/variants/HG002.snv.vcf.gz.tbi"][
            "classification"
        ]
        == "variant_vcf_index"
    )
    run_qc_html = by_path["results/runs/RUN42/run_qc/illumina/multiqc_report.html"]
    assert run_qc_html["classification"] == "multiqc_html"
    assert run_qc_html["metadata"] == {
        "barcode_ids": ["BC01", "BC02"],
        "experiment_ids": ["EXP1", "EXP2"],
        "lane_ids": ["1", "2"],
        "library_preps": ["PCR-free"],
        "manifest_context_paths": ["config/samples.tsv", "config/units.tsv"],
        "report_kind": "run_qc",
        "report_name": "multiqc_report",
        "result_scope": "run",
        "run_id": "RUN42",
        "run_ids": ["RUN42"],
        "run_qc_platform": "illumina",
        "sample_names": ["HG002", "HG003"],
        "sequencing_platforms": ["NOVASEQ"],
        "sequencing_vendors": ["LSMC"],
    }
    assert "sample:HG002" in run_qc_html["tags"]
    assert "sample:HG003" in run_qc_html["tags"]
    assert "experiment:EXP1" in run_qc_html["tags"]
    assert "experiment:EXP2" in run_qc_html["tags"]
    bcl_data = by_path[
        "results/runs/RUN42/bclconvert/multiqc_report_data/multiqc_bclconvert.txt"
    ]
    assert bcl_data["classification"] == "multiqc_data_text_artifact"
    assert bcl_data["metadata"]["report_kind"] == "bclconvert"
    assert bcl_data["metadata"]["sample_names"] == ["HG002", "HG003"]
    assert bcl_data["metadata"]["experiment_ids"] == ["EXP1", "EXP2"]
    assert "multiqc" in bcl_data["tags"]
    assert "report_kind:bclconvert" in bcl_data["tags"]
    assert by_path["results/runs/RUN42/bclconvert/metrics/rollup.json"][
        "parser_relevant"
    ] is True
    samples_record = by_path["config/samples.tsv"]
    units_record = by_path["config/units.tsv"]
    assert samples_record["classification"] == "samples_manifest"
    assert units_record["classification"] == "units_manifest"
    assert "manifest:samples" in samples_record["tags"]
    assert "manifest:units" in units_record["tags"]
    assert samples_record["metadata"]["sample_names"] == ["HG002", "HG003"]
    assert units_record["metadata"]["experiment_ids"] == ["EXP1", "EXP2"]
    assert str(output.relative_to(tmp_path)) not in by_path


def test_analysis_inventory_fails_when_no_first_class_artifacts(tmp_path: Path) -> None:
    _write(tmp_path / "notes.txt", "not under a discovery root\n")

    with pytest.raises(EvidenceManifestError, match="No first-class evidence artifacts"):
        build_analysis_evidence_manifest(
            analysis_root=tmp_path,
            output_manifest=tmp_path / "manifest.json",
            metadata=_metadata(),
            generated_at=FIXED_TIME,
        )


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
            ":(exclude)docs/jem_working_docs/**",
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
