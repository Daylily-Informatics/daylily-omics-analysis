from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class EvidenceManifestError(ValueError):
    """Raised when DayOA cannot produce deterministic local evidence."""


CANONICAL_JSON_KWARGS = {
    "sort_keys": True,
    "separators": (",", ":"),
    "ensure_ascii": True,
}

PRETTY_JSON_KWARGS = {
    "sort_keys": True,
    "indent": 2,
    "ensure_ascii": True,
}

MULTIQC_REQUIRED_DATA_FILES = (
    "multiqc_data.json",
    "multiqc_general_stats.txt",
    "multiqc_sources.txt",
    "multiqc.log",
)

FIRST_CLASS_DISCOVERY_ROOTS = ("config", "results")
GENERIC_NON_DISCOVERY_CLASSIFICATIONS = {
    "json_artifact",
    "tsv_artifact",
    "unknown",
}
HEAVYWEIGHT_DISCOVERY_CLASSIFICATIONS = {
    "alignment_bam",
    "alignment_bam_index",
    "alignment_cram",
    "alignment_cram_index",
    "csi_index",
    "variant_vcf",
    "variant_vcf_index",
}
DAY_RESULT_RESERVED_DIRS = {
    "benchmarks",
    "compiled_impute_results",
    "logs",
    "other_reports",
    "reports",
}
MANIFEST_CONTEXT_COLUMNS = {
    "sample_names": ("SAMPLEID",),
    "experiment_ids": ("EXPERIMENTID",),
    "run_ids": ("RUNID",),
    "lane_ids": ("LANEID",),
    "barcode_ids": ("BARCODEID",),
    "library_preps": ("LIBPREP",),
    "sequencing_vendors": ("SEQ_VENDOR",),
    "sequencing_platforms": ("SEQ_PLATFORM",),
}


@dataclass(frozen=True)
class EvidenceMetadata:
    pipeline_name: str
    pipeline_version: str
    git_sha: str
    snakemake_version: str
    workflow_config_hash: str
    workflow_profile: str
    genome_build: str = ""
    analysis_name: str = ""
    run_name: str = ""
    producer_system: str = "daylily-omics-analysis"
    container_images: tuple[str, ...] = ()
    references: tuple[str, ...] = ()
    provenance_refs: dict[str, str] = field(default_factory=dict)

    def validate(self) -> None:
        missing = [
            field_name
            for field_name in (
                "pipeline_name",
                "pipeline_version",
                "git_sha",
                "snakemake_version",
                "workflow_config_hash",
                "workflow_profile",
            )
            if not str(getattr(self, field_name, "")).strip()
        ]
        if missing:
            raise EvidenceManifestError(
                "Evidence metadata is missing required field(s): " + ", ".join(missing)
            )


@dataclass(frozen=True)
class ManifestTagContext:
    sample_names: tuple[str, ...] = ()
    experiment_ids: tuple[str, ...] = ()
    run_ids: tuple[str, ...] = ()
    lane_ids: tuple[str, ...] = ()
    barcode_ids: tuple[str, ...] = ()
    library_preps: tuple[str, ...] = ()
    sequencing_vendors: tuple[str, ...] = ()
    sequencing_platforms: tuple[str, ...] = ()
    source_paths: tuple[str, ...] = ()


def utc_now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json_bytes(payload: Any) -> bytes:
    return json.dumps(payload, **CANONICAL_JSON_KWARGS).encode("utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, **PRETTY_JSON_KWARGS) + "\n", encoding="utf-8")


def manifest_checksum(payload: dict[str, Any]) -> str:
    material = dict(payload)
    material.pop("manifest_checksum", None)
    return hashlib.sha256(canonical_json_bytes(material)).hexdigest()


def add_manifest_checksum(payload: dict[str, Any]) -> dict[str, Any]:
    material = dict(payload)
    material["manifest_checksum"] = manifest_checksum(material)
    return material


def current_git_sha(repo_root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise EvidenceManifestError(f"Unable to determine git SHA for {repo_root}") from exc


def snakemake_version() -> str:
    try:
        return subprocess.check_output(
            ["snakemake", "--version"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise EvidenceManifestError("Unable to determine Snakemake version.") from exc


def _has_any_suffix(name: str, suffixes: tuple[str, ...]) -> bool:
    return any(name.endswith(suffix) for suffix in suffixes)


def _is_multiqc_data_dir_name(name: str) -> bool:
    return (
        name == "multiqc_report_data"
        or name.endswith("_multiqc_data")
        or name.endswith(".multiqc_data")
    )


def _is_multiqc_data_dir_member(path: Path) -> bool:
    return any(_is_multiqc_data_dir_name(part) for part in path.parts[:-1])


def _is_multiqc_report_html(path: Path) -> bool:
    name = path.name
    parts = set(path.parts)
    if name.startswith("DAY_") and name.endswith("_multiqc.html"):
        return True
    if name == "multiqc_report.html" and ({"run_qc", "bclconvert"} & parts):
        return True
    if name.endswith(".multiqc.html") and ({"run_qc", "bclconvert"} & parts):
        return True
    return False


def _known_artifact_format(classification: str) -> str:
    return {
        "alignment_bam": "bam",
        "alignment_bam_index": "bam_index",
        "alignment_cram": "cram",
        "alignment_cram_index": "cram_index",
        "csi_index": "csi_index",
        "variant_vcf": "vcf",
        "variant_vcf_index": "vcf_index",
    }.get(classification, "")


def _read_manifest_table(path: Path, *, required_columns: set[str]) -> tuple[list[str], list[dict[str, str]]]:
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            fieldnames = [str(field or "").strip() for field in (reader.fieldnames or [])]
            missing = required_columns - set(fieldnames)
            if missing:
                raise EvidenceManifestError(
                    f"{path} is missing required metadata column(s): "
                    + ", ".join(sorted(missing))
                )
            rows = [
                {str(key or "").strip(): str(value or "").strip() for key, value in row.items()}
                for row in reader
            ]
    except OSError as exc:
        raise EvidenceManifestError(f"Unable to read manifest table: {path}") from exc
    return fieldnames, rows


def _unique_values(rows: list[dict[str, str]], columns: tuple[str, ...]) -> tuple[str, ...]:
    values: set[str] = set()
    for row in rows:
        for column in columns:
            value = str(row.get(column, "")).strip()
            if value:
                values.add(value)
    return tuple(sorted(values))


def build_manifest_tag_context(analysis_root: Path) -> ManifestTagContext:
    config_dir = analysis_root / "config"
    samples_path = config_dir / "samples.tsv"
    units_path = config_dir / "units.tsv"
    sample_rows: list[dict[str, str]] = []
    unit_rows: list[dict[str, str]] = []
    source_paths: list[str] = []

    if samples_path.is_file():
        _fieldnames, sample_rows = _read_manifest_table(
            samples_path,
            required_columns={"SAMPLEID"},
        )
        source_paths.append(relative_to_root(samples_path, analysis_root))
    if units_path.is_file():
        _fieldnames, unit_rows = _read_manifest_table(
            units_path,
            required_columns={"SAMPLEID", "EXPERIMENTID"},
        )
        source_paths.append(relative_to_root(units_path, analysis_root))

    sample_names = tuple(
        sorted(
            {
                *_unique_values(sample_rows, MANIFEST_CONTEXT_COLUMNS["sample_names"]),
                *_unique_values(unit_rows, MANIFEST_CONTEXT_COLUMNS["sample_names"]),
            }
        )
    )
    return ManifestTagContext(
        sample_names=sample_names,
        experiment_ids=_unique_values(unit_rows, MANIFEST_CONTEXT_COLUMNS["experiment_ids"]),
        run_ids=_unique_values(unit_rows, MANIFEST_CONTEXT_COLUMNS["run_ids"]),
        lane_ids=_unique_values(unit_rows, MANIFEST_CONTEXT_COLUMNS["lane_ids"]),
        barcode_ids=_unique_values(unit_rows, MANIFEST_CONTEXT_COLUMNS["barcode_ids"]),
        library_preps=_unique_values(unit_rows, MANIFEST_CONTEXT_COLUMNS["library_preps"]),
        sequencing_vendors=_unique_values(
            unit_rows,
            MANIFEST_CONTEXT_COLUMNS["sequencing_vendors"],
        ),
        sequencing_platforms=_unique_values(
            unit_rows,
            MANIFEST_CONTEXT_COLUMNS["sequencing_platforms"],
        ),
        source_paths=tuple(source_paths),
    )


def _multiqc_report_metadata(path: Path) -> dict[str, str]:
    parts = path.parts
    name = path.name
    metadata: dict[str, str] = {}

    data_dir = next((part for part in parts if _is_multiqc_data_dir_name(part)), "")
    report_name = ""
    if data_dir:
        report_name = data_dir
    elif name.endswith(".html") and _is_multiqc_report_html(path):
        report_name = name.removesuffix(".html")
    if report_name.endswith("_data"):
        report_name = report_name[: -len("_data")]
    if report_name.endswith(".multiqc_data"):
        report_name = report_name[: -len(".multiqc_data")]
    if report_name == "multiqc_report_data":
        report_name = "multiqc_report"
    if report_name:
        metadata["report_name"] = report_name

    if "bclconvert" in parts:
        metadata["report_kind"] = "bclconvert"
        return metadata

    if "run_qc" in parts:
        metadata["report_kind"] = "run_qc"
        index = parts.index("run_qc")
        if len(parts) > index + 1:
            metadata["run_qc_platform"] = parts[index + 1]
        return metadata

    if report_name.startswith("DAY_") and report_name.endswith("_multiqc"):
        metadata["report_kind"] = report_name[len("DAY_") : -len("_multiqc")]
    return metadata


def artifact_metadata(relative_path: str, classification: str) -> dict[str, Any]:
    path = Path(relative_path)
    parts = path.parts
    metadata: dict[str, str] = {}

    if len(parts) >= 3 and parts[0] == "results" and parts[1] == "day":
        metadata["result_scope"] = "day"
        metadata["genome_build"] = parts[2]
        if len(parts) >= 4 and parts[3] not in DAY_RESULT_RESERVED_DIRS:
            metadata["sample_id"] = parts[3]
    elif len(parts) >= 3 and parts[0] == "results" and parts[1] == "runs":
        metadata["result_scope"] = "run"
        metadata["run_id"] = parts[2]

    artifact_format = _known_artifact_format(classification)
    if artifact_format:
        metadata["artifact_format"] = artifact_format

    if classification.startswith("multiqc_") or classification in {
        "bclconvert_json",
        "bclconvert_table",
        "custom_mqc_tsv",
        "run_qc_json",
        "run_qc_tsv",
        "staging_manifest",
    }:
        metadata.update(_multiqc_report_metadata(path))

    return metadata


def _context_metadata(context: ManifestTagContext) -> dict[str, Any]:
    metadata: dict[str, Any] = {}
    for field_name in (
        "sample_names",
        "experiment_ids",
        "run_ids",
        "lane_ids",
        "barcode_ids",
        "library_preps",
        "sequencing_vendors",
        "sequencing_platforms",
    ):
        values = list(getattr(context, field_name))
        if values:
            metadata[field_name] = values
    if context.source_paths:
        metadata["manifest_context_paths"] = list(context.source_paths)
    return metadata


def _context_tags(context: ManifestTagContext) -> list[str]:
    tag_groups = (
        ("sample", context.sample_names),
        ("experiment", context.experiment_ids),
        ("run", context.run_ids),
        ("lane", context.lane_ids),
        ("barcode", context.barcode_ids),
        ("libprep", context.library_preps),
        ("seq_vendor", context.sequencing_vendors),
        ("seq_platform", context.sequencing_platforms),
    )
    return [
        f"{prefix}:{value}"
        for prefix, values in tag_groups
        for value in values
    ]


def artifact_tags(
    relative_path: str,
    classification: str,
    metadata: dict[str, Any],
    context: ManifestTagContext,
) -> list[str]:
    tags: set[str] = {f"artifact_role:{classification}"}
    if relative_path == "config/samples.tsv":
        tags.add("manifest:samples")
    if relative_path == "config/units.tsv":
        tags.add("manifest:units")
    if classification == "multiqc_html" or classification.startswith("multiqc_"):
        tags.add("multiqc")
        report_kind = str(metadata.get("report_kind") or "").strip()
        if report_kind:
            tags.add(f"report_kind:{report_kind}")
        tags.update(_context_tags(context))
    if classification in {"samples_manifest", "units_manifest"}:
        tags.update(_context_tags(context))
    return sorted(tags)


def file_classification(relative_path: str) -> tuple[str, bool]:
    path = Path(relative_path)
    name = path.name
    lower_name = name.lower()
    parts = set(path.parts)

    if _has_any_suffix(lower_name, (".vcf.gz.tbi", ".vcf.tbi", ".vcf.gz.csi", ".vcf.csi")):
        return "variant_vcf_index", False
    if _has_any_suffix(lower_name, (".vcf.gz", ".vcf")):
        return "variant_vcf", False
    if lower_name.endswith(".cram.crai") or lower_name.endswith(".crai"):
        return "alignment_cram_index", False
    if lower_name.endswith(".cram"):
        return "alignment_cram", False
    if lower_name.endswith(".bam.bai") or lower_name.endswith(".bai"):
        return "alignment_bam_index", False
    if lower_name.endswith(".bam.csi"):
        return "alignment_bam_index", False
    if lower_name.endswith(".bam"):
        return "alignment_bam", False
    if lower_name.endswith(".csi"):
        return "csi_index", False

    if _is_multiqc_report_html(path):
        return "multiqc_html", True
    if name == "multiqc_data.json":
        return "multiqc_data_json", True
    if name == "multiqc_general_stats.txt":
        return "multiqc_general_stats", True
    if name == "multiqc_sources.txt":
        return "multiqc_sources", True
    if name == "multiqc.log":
        return "multiqc_log", True
    if _is_multiqc_data_dir_member(path):
        if lower_name.endswith(".json"):
            return "multiqc_data_json_artifact", True
        if _has_any_suffix(lower_name, (".tsv", ".csv")):
            return "multiqc_data_table_artifact", True
        if lower_name.endswith(".txt"):
            return "multiqc_data_text_artifact", True
        if lower_name.endswith(".log"):
            return "multiqc_log", True
        return "multiqc_data_artifact", False
    if name.endswith("_mqc.tsv"):
        return "custom_mqc_tsv", True
    if name == "manifest.tsv" and "multiqc_inputs" in parts:
        return "staging_manifest", True
    if name == "samples.tsv" and path.parts[:1] == ("config",):
        return "samples_manifest", True
    if name == "units.tsv" and path.parts[:1] == ("config",):
        return "units_manifest", True
    if "run_qc" in parts and lower_name.endswith(".json"):
        return "run_qc_json", True
    if "run_qc" in parts and lower_name.endswith(".tsv"):
        return "run_qc_tsv", True
    if "bclconvert" in parts and lower_name.endswith(".json"):
        return "bclconvert_json", True
    if "bclconvert" in parts and _has_any_suffix(lower_name, (".tsv", ".csv")):
        return "bclconvert_table", True
    if name.endswith(".bench.tsv") or name == "benchmarks_summary.tsv":
        return "benchmark", False
    if name.endswith(".log") or "logs" in parts:
        return "log", False
    if name.endswith(".json"):
        return "json_artifact", False
    if name.endswith(".tsv"):
        return "tsv_artifact", False
    if name.endswith(".html"):
        return "html_artifact", False
    if name.endswith(".mmd"):
        return "workflow_diagram_source", False
    if name.endswith(".pdf"):
        return "workflow_diagram_pdf", False
    if name.endswith(".md"):
        return "workflow_report", False
    return "unknown", False


def include_discovered_evidence(relative_path: str) -> bool:
    classification, _parser_relevant = file_classification(relative_path)
    return classification not in GENERIC_NON_DISCOVERY_CLASSIFICATIONS


def lexical_absolute_path(path: Path, root: Path) -> Path:
    """Return an absolute path without resolving symlink targets."""
    root_abs = Path(os.path.abspath(root))
    candidate = path if path.is_absolute() else root_abs / path
    return Path(os.path.abspath(candidate))


def relative_to_root(path: Path, root: Path) -> str:
    root_abs = Path(os.path.abspath(root))
    path_abs = lexical_absolute_path(path, root_abs)
    try:
        rel_path = path_abs.relative_to(root_abs).as_posix()
    except ValueError as exc:
        raise EvidenceManifestError(f"Evidence path is outside analysis root: {path}") from exc
    if rel_path == ".." or rel_path.startswith("../") or Path(rel_path).is_absolute():
        raise EvidenceManifestError(f"Evidence path is not relative to analysis root: {path}")
    return rel_path


def discover_first_class_evidence_files(
    analysis_root: Path,
    *,
    output_manifest: Path | None = None,
    include_heavyweight: bool = True,
) -> list[Path]:
    excluded: set[Path] = set()
    if output_manifest is not None:
        excluded.add(lexical_absolute_path(output_manifest, analysis_root))

    discovered: dict[str, Path] = {}
    for root_name in FIRST_CLASS_DISCOVERY_ROOTS:
        root = analysis_root / root_name
        if not root.exists():
            continue
        if not root.is_dir():
            raise EvidenceManifestError(f"Evidence discovery root is not a directory: {root}")
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            local_path = lexical_absolute_path(path, analysis_root)
            if local_path in excluded:
                continue
            rel_path = relative_to_root(path, analysis_root)
            classification, _parser_relevant = file_classification(rel_path)
            if not include_heavyweight and classification in HEAVYWEIGHT_DISCOVERY_CLASSIFICATIONS:
                continue
            if include_discovered_evidence(rel_path):
                discovered[rel_path] = local_path
    return [discovered[key] for key in sorted(discovered)]


def collect_inventory(
    *,
    analysis_root: Path,
    file_paths: list[Path],
    directory_paths: list[Path] | None = None,
    required_paths: list[Path] | None = None,
    include_heavyweight: bool = True,
) -> list[dict[str, Any]]:
    required_paths = required_paths or []
    required_rel = {relative_to_root(path, analysis_root) for path in required_paths}
    missing = [path for path in required_paths if not path.is_file()]
    if missing:
        raise EvidenceManifestError(
            "Required evidence file(s) are missing: "
            + ", ".join(str(path) for path in sorted(missing))
        )

    candidates: dict[str, Path] = {}
    for path in file_paths:
        if path.is_file():
            candidates[relative_to_root(path, analysis_root)] = lexical_absolute_path(path, analysis_root)
        elif path in required_paths:
            raise EvidenceManifestError(f"Required evidence file is missing: {path}")

    for directory in directory_paths or []:
        if not directory.is_dir():
            raise EvidenceManifestError(f"Required evidence directory is missing: {directory}")
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                candidates[relative_to_root(path, analysis_root)] = lexical_absolute_path(path, analysis_root)

    records: list[dict[str, Any]] = []
    tag_context = build_manifest_tag_context(analysis_root)
    for rel_path, abs_path in sorted(candidates.items()):
        classification, parser_relevant = file_classification(rel_path)
        if (
            not include_heavyweight
            and rel_path not in required_rel
            and classification in HEAVYWEIGHT_DISCOVERY_CLASSIFICATIONS
        ):
            continue
        record = {
            "relative_path": rel_path,
            "size_bytes": abs_path.stat().st_size,
            "sha256": sha256_file(abs_path),
            "classification": classification,
            "parser_relevant": parser_relevant,
            "required": rel_path in required_rel,
            "artifact_kind": "file",
        }
        metadata = artifact_metadata(rel_path, classification)
        if classification in {"samples_manifest", "units_manifest"} or (
            classification == "multiqc_html" or classification.startswith("multiqc_")
        ):
            metadata.update(_context_metadata(tag_context))
        tags = artifact_tags(rel_path, classification, metadata, tag_context)
        if metadata:
            record["metadata"] = metadata
        if tags:
            record["tags"] = tags
        records.append(record)
    return records


def without_heavyweight_files(analysis_root: Path, file_paths: list[Path]) -> list[Path]:
    """Remove heavyweight alignment/variant files from report evidence hashing."""
    kept: list[Path] = []
    for path in file_paths:
        rel_path = relative_to_root(path, analysis_root)
        classification, _parser_relevant = file_classification(rel_path)
        if classification in HEAVYWEIGHT_DISCOVERY_CLASSIFICATIONS:
            continue
        kept.append(path)
    return kept


def parse_stage_manifest_warnings(stage_manifest: Path) -> list[dict[str, Any]]:
    if not stage_manifest.is_file():
        raise EvidenceManifestError(f"Stage manifest is missing: {stage_manifest}")
    warnings: list[dict[str, Any]] = []
    seen_sample_groups: dict[str, set[str]] = {}
    seen_sample_bases: dict[str, set[str]] = {}
    with stage_manifest.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"Sample", "base_sample", "group_id"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise EvidenceManifestError(
                "Stage manifest is missing required column(s): " + ", ".join(sorted(missing))
            )
        for row in reader:
            sample = str(row.get("Sample", "")).strip()
            group_id = str(row.get("group_id", "")).strip()
            base_sample = str(row.get("base_sample", "")).strip()
            if not sample:
                continue
            seen_sample_groups.setdefault(sample, set()).add(group_id)
            seen_sample_bases.setdefault(sample, set()).add(base_sample)

    for sample, groups in sorted(seen_sample_groups.items()):
        cleaned = {group for group in groups if group}
        if len(cleaned) > 1:
            warnings.append(
                {
                    "warning_type": "sample_name_collision",
                    "sample": sample,
                    "group_ids": sorted(cleaned),
                }
            )
    for sample, bases in sorted(seen_sample_bases.items()):
        cleaned = {base for base in bases if base}
        if len(cleaned) > 1:
            warnings.append(
                {
                    "warning_type": "sample_base_collision",
                    "sample": sample,
                    "base_samples": sorted(cleaned),
                }
            )
    return warnings


def build_evidence_manifest(
    *,
    analysis_root: Path,
    file_paths: list[Path],
    directory_paths: list[Path] | None,
    required_paths: list[Path],
    output_manifest: Path,
    metadata: EvidenceMetadata,
    manifest_kind: str = "dayoa.analysis_evidence",
    include_heavyweight: bool = True,
    warnings: list[dict[str, Any]] | None = None,
    generated_at: str | None = None,
) -> dict[str, Any]:
    generated_at = generated_at or utc_now_iso()
    metadata.validate()
    inventory = collect_inventory(
        analysis_root=analysis_root,
        file_paths=file_paths,
        directory_paths=directory_paths or [],
        required_paths=required_paths,
        include_heavyweight=include_heavyweight,
    )
    manifest = add_manifest_checksum(
        {
            "schema_version": "dayoa.evidence_manifest.v1",
            "manifest_kind": manifest_kind,
            "generated_at": generated_at,
            "producer": {
                "system": metadata.producer_system,
                "role": "execution_plane",
                "registration_side_effects": False,
            },
            "analysis": {
                "analysis_name": metadata.analysis_name,
                "run_name": metadata.run_name,
                "genome_build": metadata.genome_build,
            },
            "workflow": {
                "pipeline_name": metadata.pipeline_name,
                "pipeline_version": metadata.pipeline_version,
                "git_sha": metadata.git_sha,
                "snakemake_version": metadata.snakemake_version,
                "workflow_config_hash": metadata.workflow_config_hash,
                "workflow_profile": metadata.workflow_profile,
                "container_images": list(metadata.container_images),
                "references": list(metadata.references),
            },
            "artifact_boundaries": {
                "dayoa_emits_local_evidence_only": True,
                "multiqc_html_is_canonical_data": False,
                "downstream_registration_owner": "external_orchestrator",
                "qc_interpretation_authority": "downstream_qc_service",
            },
            "root_analysis_dir": {
                "relative_path": ".",
            },
            "provenance_refs": metadata.provenance_refs,
            "required_files": [relative_to_root(path, analysis_root) for path in required_paths],
            "files": inventory,
            "warnings": warnings or [],
        }
    )
    write_json(output_manifest, manifest)
    return manifest


def build_analysis_evidence_manifest(
    *,
    analysis_root: Path,
    output_manifest: Path,
    metadata: EvidenceMetadata,
    required_paths: list[Path] | None = None,
    manifest_kind: str = "dayoa.analysis_evidence",
    generated_at: str | None = None,
) -> dict[str, Any]:
    required_paths = required_paths or []
    file_paths = discover_first_class_evidence_files(
        analysis_root,
        output_manifest=output_manifest,
    )
    for path in required_paths:
        file_paths.append(path)
    if not file_paths:
        raise EvidenceManifestError(
            f"No first-class evidence artifacts discovered under {analysis_root}"
        )
    return build_evidence_manifest(
        analysis_root=analysis_root,
        file_paths=file_paths,
        directory_paths=[],
        required_paths=required_paths,
        output_manifest=output_manifest,
        metadata=metadata,
        manifest_kind=manifest_kind,
        generated_at=generated_at,
    )


def build_multiqc_final_evidence_manifest(
    *,
    analysis_root: Path,
    html_path: Path,
    multiqc_data_dir: Path,
    stage_manifest: Path,
    parser_relevant_paths: list[Path],
    output_manifest: Path,
    metadata: EvidenceMetadata,
    generated_at: str | None = None,
) -> dict[str, Any]:
    required_paths = [html_path, stage_manifest] + [
        multiqc_data_dir / name for name in MULTIQC_REQUIRED_DATA_FILES
    ]
    file_paths = (
        without_heavyweight_files(
            analysis_root,
            [html_path, stage_manifest] + parser_relevant_paths,
        )
        + discover_first_class_evidence_files(
            analysis_root,
            output_manifest=output_manifest,
            include_heavyweight=False,
        )
    )
    return build_evidence_manifest(
        analysis_root=analysis_root,
        file_paths=file_paths,
        directory_paths=[multiqc_data_dir],
        required_paths=required_paths,
        output_manifest=output_manifest,
        metadata=metadata,
        manifest_kind="dayoa.multiqc_final_evidence",
        include_heavyweight=False,
        warnings=parse_stage_manifest_warnings(stage_manifest),
        generated_at=generated_at,
    )


def _metadata_from_args(args: argparse.Namespace) -> EvidenceMetadata:
    provenance_refs = {}
    for item in args.provenance_ref:
        if "=" not in item:
            raise EvidenceManifestError(
                "--provenance-ref must use key=value syntax, got: " + item
            )
        key, value = item.split("=", 1)
        provenance_refs[key] = value
    return EvidenceMetadata(
        pipeline_name=args.pipeline_name,
        pipeline_version=args.pipeline_version,
        git_sha=args.git_sha,
        snakemake_version=args.snakemake_version,
        workflow_config_hash=args.workflow_config_hash,
        workflow_profile=args.workflow_profile,
        genome_build=args.genome_build,
        analysis_name=args.analysis_name,
        run_name=args.run_name,
        container_images=tuple(args.container_image),
        references=tuple(args.reference),
        provenance_refs=provenance_refs,
    )


def _add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--analysis-root", required=True)
    parser.add_argument("--analysis-name", default="")
    parser.add_argument("--run-name", default="")
    parser.add_argument("--genome-build", default="")
    parser.add_argument("--pipeline-name", required=True)
    parser.add_argument("--pipeline-version", required=True)
    parser.add_argument("--git-sha", required=True)
    parser.add_argument("--snakemake-version", required=True)
    parser.add_argument("--workflow-config-hash", required=True)
    parser.add_argument("--workflow-profile", required=True)
    parser.add_argument("--container-image", action="append", default=[])
    parser.add_argument("--reference", action="append", default=[])
    parser.add_argument("--provenance-ref", action="append", default=[])
    parser.add_argument("--generated-at", default="")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Write DayOA local evidence manifests.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    multiqc = subparsers.add_parser("multiqc-final")
    _add_common_args(multiqc)
    multiqc.add_argument("--html", required=True)
    multiqc.add_argument("--multiqc-data-dir", required=True)
    multiqc.add_argument("--stage-manifest", required=True)
    multiqc.add_argument("--parser-relevant", action="append", default=[])
    multiqc.add_argument("--evidence-manifest-output", required=True)

    inventory = subparsers.add_parser("inventory")
    _add_common_args(inventory)
    inventory.add_argument("--file", action="append", required=True)
    inventory.add_argument("--directory", action="append", default=[])
    inventory.add_argument("--required-file", action="append", default=[])
    inventory.add_argument("--manifest-kind", default="dayoa.analysis_evidence")
    inventory.add_argument("--evidence-manifest-output", required=True)

    analysis_inventory = subparsers.add_parser("analysis-inventory")
    _add_common_args(analysis_inventory)
    analysis_inventory.add_argument("--required-file", action="append", default=[])
    analysis_inventory.add_argument("--manifest-kind", default="dayoa.analysis_evidence")
    analysis_inventory.add_argument("--evidence-manifest-output", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    try:
        metadata = _metadata_from_args(args)
        if args.command == "multiqc-final":
            build_multiqc_final_evidence_manifest(
                analysis_root=Path(args.analysis_root),
                html_path=Path(args.html),
                multiqc_data_dir=Path(args.multiqc_data_dir),
                stage_manifest=Path(args.stage_manifest),
                parser_relevant_paths=[Path(path) for path in args.parser_relevant],
                output_manifest=Path(args.evidence_manifest_output),
                metadata=metadata,
                generated_at=args.generated_at or None,
            )
        elif args.command == "inventory":
            build_evidence_manifest(
                analysis_root=Path(args.analysis_root),
                file_paths=[Path(path) for path in args.file],
                directory_paths=[Path(path) for path in args.directory],
                required_paths=[Path(path) for path in args.required_file],
                output_manifest=Path(args.evidence_manifest_output),
                metadata=metadata,
                manifest_kind=args.manifest_kind,
                generated_at=args.generated_at or None,
            )
        elif args.command == "analysis-inventory":
            build_analysis_evidence_manifest(
                analysis_root=Path(args.analysis_root),
                required_paths=[Path(path) for path in args.required_file],
                output_manifest=Path(args.evidence_manifest_output),
                metadata=metadata,
                manifest_kind=args.manifest_kind,
                generated_at=args.generated_at or None,
            )
        else:  # pragma: no cover - argparse enforces valid commands.
            raise EvidenceManifestError(f"Unknown command: {args.command}")
    except EvidenceManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
