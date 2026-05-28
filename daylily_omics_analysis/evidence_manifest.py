from __future__ import annotations

import argparse
import csv
import hashlib
import json
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


def file_classification(relative_path: str) -> tuple[str, bool]:
    path = Path(relative_path)
    name = path.name
    parts = set(path.parts)
    if name == "DAY_final_multiqc.html":
        return "multiqc_html", True
    if name == "multiqc_data.json":
        return "multiqc_data_json", True
    if name == "multiqc_general_stats.txt":
        return "multiqc_general_stats", True
    if name == "multiqc_sources.txt":
        return "multiqc_sources", True
    if name == "multiqc.log":
        return "multiqc_log", True
    if name.endswith("_mqc.tsv"):
        return "custom_mqc_tsv", True
    if name == "manifest.tsv" and "multiqc_inputs" in parts:
        return "staging_manifest", True
    if name in {"samples.tsv", "units.tsv"}:
        return "run_manifest", True
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


def relative_to_root(path: Path, root: Path) -> str:
    try:
        rel_path = path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise EvidenceManifestError(f"Evidence path is outside analysis root: {path}") from exc
    if rel_path == ".." or rel_path.startswith("../") or Path(rel_path).is_absolute():
        raise EvidenceManifestError(f"Evidence path is not relative to analysis root: {path}")
    return rel_path


def collect_inventory(
    *,
    analysis_root: Path,
    file_paths: list[Path],
    directory_paths: list[Path] | None = None,
    required_paths: list[Path] | None = None,
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
            candidates[relative_to_root(path, analysis_root)] = path.resolve()
        elif path in required_paths:
            raise EvidenceManifestError(f"Required evidence file is missing: {path}")

    for directory in directory_paths or []:
        if not directory.is_dir():
            raise EvidenceManifestError(f"Required evidence directory is missing: {directory}")
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                candidates[relative_to_root(path, analysis_root)] = path.resolve()

    records: list[dict[str, Any]] = []
    for rel_path, abs_path in sorted(candidates.items()):
        classification, parser_relevant = file_classification(rel_path)
        records.append(
            {
                "relative_path": rel_path,
                "size_bytes": abs_path.stat().st_size,
                "sha256": sha256_file(abs_path),
                "classification": classification,
                "parser_relevant": parser_relevant,
                "required": rel_path in required_rel,
                "artifact_kind": "file",
            }
        )
    return records


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
    file_paths = [html_path, stage_manifest] + parser_relevant_paths
    return build_evidence_manifest(
        analysis_root=analysis_root,
        file_paths=file_paths,
        directory_paths=[multiqc_data_dir],
        required_paths=required_paths,
        output_manifest=output_manifest,
        metadata=metadata,
        manifest_kind="dayoa.multiqc_final_evidence",
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
        else:  # pragma: no cover - argparse enforces valid commands.
            raise EvidenceManifestError(f"Unknown command: {args.command}")
    except EvidenceManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
