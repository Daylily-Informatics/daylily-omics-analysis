from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class QeoRegistrationError(ValueError):
    """Raised when DayOA cannot produce a deterministic QEO/Dewey artifact record."""


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

KEY_MULTIQC_CLASSIFICATIONS = {
    "multiqc_html",
    "multiqc_data_json",
    "multiqc_general_stats",
    "multiqc_sources",
    "multiqc_log",
    "custom_mqc_tsv",
    "staging_manifest",
}


@dataclass(frozen=True)
class RegistrationConfig:
    mode: str
    dewey_url: str = ""
    dewey_token: str = ""
    dewey_token_env: str = ""
    storage_root_uri: str = ""
    producer_system: str = "daylily-omics-analysis"

    def validate(self) -> None:
        if self.mode not in {"local_only", "dewey"}:
            raise QeoRegistrationError(
                "qeo_registration.mode must be explicitly set to 'local_only' or 'dewey'."
            )
        if self.mode == "dewey":
            missing = []
            if not self.dewey_url.strip():
                missing.append("dewey_url")
            if not self.storage_root_uri.strip():
                missing.append("storage_root_uri")
            if not self.token:
                token_name = self.dewey_token_env or "dewey_token/dewey_token_env"
                missing.append(token_name)
            if missing:
                raise QeoRegistrationError(
                    "Dewey registration mode requires explicit config value(s): "
                    + ", ".join(missing)
                )

    @property
    def token(self) -> str:
        if self.dewey_token:
            return self.dewey_token
        if self.dewey_token_env:
            return os.environ.get(self.dewey_token_env, "")
        return ""


def utc_now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json_bytes(payload: Any) -> bytes:
    return json.dumps(payload, **CANONICAL_JSON_KWARGS).encode("utf-8")


def stable_sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


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


def require_metadata(metadata: dict[str, Any], required_fields: tuple[str, ...]) -> None:
    missing = [field for field in required_fields if not str(metadata.get(field, "")).strip()]
    if missing:
        raise QeoRegistrationError(
            "QEO registration metadata is missing required field(s): " + ", ".join(missing)
        )


def current_git_sha(repo_root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise QeoRegistrationError(f"Unable to determine git SHA for {repo_root}") from exc


def snakemake_version() -> str:
    try:
        return subprocess.check_output(
            ["snakemake", "--version"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise QeoRegistrationError("Unable to determine Snakemake version.") from exc


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
    return "unknown", False


def relative_to_root(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise QeoRegistrationError(f"Artifact path is outside analysis root: {path}") from exc


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
        raise QeoRegistrationError(
            "Required artifact file(s) are missing: "
            + ", ".join(str(path) for path in sorted(missing))
        )

    candidates: dict[str, Path] = {}
    for path in file_paths:
        if path.is_file():
            candidates[relative_to_root(path, analysis_root)] = path.resolve()
        elif path in required_paths:
            raise QeoRegistrationError(f"Required artifact file is missing: {path}")

    for directory in directory_paths or []:
        if not directory.is_dir():
            raise QeoRegistrationError(f"Required artifact directory is missing: {directory}")
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
        raise QeoRegistrationError(f"Stage manifest is missing: {stage_manifest}")
    warnings: list[dict[str, Any]] = []
    seen_sample_groups: dict[str, set[str]] = {}
    seen_sample_bases: dict[str, set[str]] = {}
    with stage_manifest.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"Sample", "base_sample", "group_id"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise QeoRegistrationError(
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


def artifact_intents_for_manifest(
    *,
    manifest: dict[str, Any],
    analysis_root: Path,
    multiqc_data_dir: Path | None = None,
    include_all_files: bool = False,
) -> list[dict[str, Any]]:
    checksum = manifest["manifest_checksum"]
    intents = [
        {
            "intent_id": "analysis_root",
            "artifact_type": "dayoa.analysis_root",
            "storage_kind": "prefix",
            "node_kind": "directory",
            "relative_path": ".",
            "manifest_checksum": checksum,
        }
    ]
    if multiqc_data_dir is not None:
        intents.append(
            {
                "intent_id": "multiqc_data_directory",
                "artifact_type": "dayoa.multiqc_data_directory",
                "storage_kind": "prefix",
                "node_kind": "directory",
                "relative_path": relative_to_root(multiqc_data_dir, analysis_root),
                "manifest_checksum": checksum,
            }
        )

    for record in manifest["files"]:
        if (
            include_all_files
            or record["classification"] in KEY_MULTIQC_CLASSIFICATIONS
            or record["parser_relevant"]
        ):
            intents.append(
                {
                    "intent_id": record["relative_path"],
                    "artifact_type": f"dayoa.{record['classification']}",
                    "storage_kind": "file",
                    "node_kind": "file",
                    "relative_path": record["relative_path"],
                    "sha256": record["sha256"],
                    "size_bytes": record["size_bytes"],
                    "classification": record["classification"],
                    "parser_relevant": record["parser_relevant"],
                    "manifest_checksum": checksum,
                }
            )
    return intents


def local_receipt(
    *,
    manifest: dict[str, Any],
    artifact_intents: list[dict[str, Any]],
    generated_at: str,
) -> dict[str, Any]:
    artifacts = []
    for intent in artifact_intents:
        identity_material = canonical_json_bytes(
            {
                "relative_path": intent["relative_path"],
                "artifact_type": intent["artifact_type"],
                "manifest_checksum": intent["manifest_checksum"],
                "sha256": intent.get("sha256", ""),
            }
        )
        local_id = hashlib.sha256(identity_material).hexdigest()
        artifacts.append(
            {
                "intent_id": intent["intent_id"],
                "artifact_ref": f"local-{intent['storage_kind']}-sha256:{local_id}",
                "artifact_type": intent["artifact_type"],
                "relative_path": intent["relative_path"],
                "storage_kind": intent["storage_kind"],
                "node_kind": intent["node_kind"],
                "registration_status": "local_only",
            }
        )
    artifact_set_material = {
        "analysis_euid": manifest["analysis"]["analysis_euid"],
        "run_euid": manifest["analysis"]["run_euid"],
        "manifest_checksum": manifest["manifest_checksum"],
        "artifact_refs": [artifact["artifact_ref"] for artifact in artifacts],
    }
    artifact_set_ref = "local-artifact-set-sha256:" + hashlib.sha256(
        canonical_json_bytes(artifact_set_material)
    ).hexdigest()
    return {
        "schema_version": "dayoa.dewey_receipt.v1",
        "registration_mode": "local_only",
        "registration_status": "local_only",
        "generated_at": generated_at,
        "manifest_checksum": manifest["manifest_checksum"],
        "artifacts": artifacts,
        "artifact_sets": [
            {
                "artifact_set_ref": artifact_set_ref,
                "artifact_set_type": manifest["manifest_kind"],
                "registration_status": "local_only",
                "member_count": len(artifacts),
            }
        ],
    }


def dewey_idempotency_key(*, producer_system: str, artifact_type: str, identity: str) -> str:
    return "dayoa:" + stable_sha256_text(
        canonical_json_bytes(
            {
                "producer_system": producer_system,
                "artifact_type": artifact_type,
                "identity": identity,
            }
        ).decode("utf-8")
    )


def join_storage_uri(storage_root_uri: str, relative_path: str) -> str:
    root = storage_root_uri.rstrip("/")
    if relative_path == ".":
        return root + "/"
    return root + "/" + urllib.parse.quote(relative_path, safe="/._-")


def parse_s3_uri(uri: str) -> tuple[str, str]:
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "s3" or not parsed.netloc:
        raise QeoRegistrationError(f"Dewey registration requires s3:// storage URIs, got: {uri}")
    return parsed.netloc, parsed.path.lstrip("/")


def post_json(url: str, token: str, payload: dict[str, Any], idempotency_key: str) -> dict[str, Any]:
    body = canonical_json_bytes(payload)
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Idempotency-Key": idempotency_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise QeoRegistrationError(f"Dewey request failed with HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise QeoRegistrationError(f"Dewey request failed: {exc}") from exc
    if not response_body.strip():
        return {}
    return json.loads(response_body)


def dewey_receipt(
    *,
    manifest: dict[str, Any],
    artifact_intents: list[dict[str, Any]],
    config: RegistrationConfig,
    generated_at: str,
) -> dict[str, Any]:
    config.validate()
    base_url = config.dewey_url.rstrip("/")
    artifacts = []
    for intent in artifact_intents:
        storage_uri = join_storage_uri(config.storage_root_uri, intent["relative_path"])
        bucket, key = parse_s3_uri(storage_uri.rstrip("/"))
        identity = canonical_json_bytes(
            {
                "storage_uri": storage_uri,
                "artifact_type": intent["artifact_type"],
                "manifest_checksum": manifest["manifest_checksum"],
                "sha256": intent.get("sha256", ""),
            }
        ).decode("utf-8")
        payload = {
            "artifact_type": intent["artifact_type"],
            "storage_kind": intent["storage_kind"],
            "node_kind": intent["node_kind"],
            "storage_backend": "s3",
            "bucket": bucket,
            "key": key,
            "checksum": intent.get("sha256", intent["manifest_checksum"]),
            "size": intent.get("size_bytes"),
            "producer_system": config.producer_system,
            "producer_object_euid": manifest["analysis"]["analysis_euid"],
            "source_uri": storage_uri,
            "metadata": {
                "relative_path": intent["relative_path"],
                "manifest_checksum": manifest["manifest_checksum"],
                "classification": intent.get("classification"),
                "parser_relevant": intent.get("parser_relevant", False),
            },
        }
        response = post_json(
            base_url + "/api/v1/artifacts",
            config.token,
            payload,
            dewey_idempotency_key(
                producer_system=config.producer_system,
                artifact_type=intent["artifact_type"],
                identity=identity,
            ),
        )
        artifacts.append(
            {
                "intent_id": intent["intent_id"],
                "artifact_ref": response.get("artifact_euid") or response.get("euid"),
                "artifact_type": intent["artifact_type"],
                "relative_path": intent["relative_path"],
                "storage_uri": storage_uri,
                "request": payload,
                "response": response,
                "registration_status": "registered",
            }
        )
    set_payload = {
        "artifact_set_type": manifest["manifest_kind"],
        "metadata": {
            "analysis_euid": manifest["analysis"]["analysis_euid"],
            "run_euid": manifest["analysis"]["run_euid"],
            "manifest_checksum": manifest["manifest_checksum"],
        },
        "artifact_euids": [
            artifact["artifact_ref"] for artifact in artifacts if artifact.get("artifact_ref")
        ],
    }
    set_response = post_json(
        base_url + "/api/v1/artifact-sets",
        config.token,
        set_payload,
        dewey_idempotency_key(
            producer_system=config.producer_system,
            artifact_type=manifest["manifest_kind"],
            identity=manifest["manifest_checksum"],
        ),
    )
    return {
        "schema_version": "dayoa.dewey_receipt.v1",
        "registration_mode": "dewey",
        "registration_status": "registered",
        "generated_at": generated_at,
        "manifest_checksum": manifest["manifest_checksum"],
        "artifacts": artifacts,
        "artifact_sets": [
            {
                "artifact_set_ref": set_response.get("artifact_set_euid") or set_response.get("euid"),
                "artifact_set_type": manifest["manifest_kind"],
                "registration_status": "registered",
                "member_count": len(artifacts),
                "request": set_payload,
                "response": set_response,
            }
        ],
    }


def register_artifacts(
    *,
    manifest: dict[str, Any],
    artifact_intents: list[dict[str, Any]],
    config: RegistrationConfig,
    generated_at: str,
) -> dict[str, Any]:
    config.validate()
    if config.mode == "local_only":
        return local_receipt(
            manifest=manifest,
            artifact_intents=artifact_intents,
            generated_at=generated_at,
        )
    return dewey_receipt(
        manifest=manifest,
        artifact_intents=artifact_intents,
        config=config,
        generated_at=generated_at,
    )


def qeo_ingest_manifest(
    *,
    manifest: dict[str, Any],
    receipt: dict[str, Any],
    generated_at: str,
    parser_family: str,
) -> dict[str, Any]:
    artifacts_by_path = {
        artifact["relative_path"]: artifact
        for artifact in receipt.get("artifacts", [])
        if artifact.get("relative_path")
    }
    parser_hints = []
    for record in manifest["files"]:
        if not record["parser_relevant"]:
            continue
        receipt_artifact = artifacts_by_path.get(record["relative_path"], {})
        parser_hints.append(
            {
                "relative_path": record["relative_path"],
                "classification": record["classification"],
                "required": record["required"],
                "sha256": record["sha256"],
                "artifact_ref": receipt_artifact.get("artifact_ref"),
            }
        )
    payload = {
        "schema_version": "qeo.ingest_manifest.v1",
        "generated_at": generated_at,
        "parser_family": parser_family,
        "parser_schema_version": "qeo-parser-v0",
        "metric_dictionary_version": "qeo-metric-dictionary-v0",
        "source_manifest_checksum": manifest["manifest_checksum"],
        "dewey_receipt_checksum": manifest_checksum(receipt),
        "analysis_linkage": manifest["analysis"],
        "lineage_refs": {
            "pipeline_name": manifest["workflow"]["pipeline_name"],
            "pipeline_version": manifest["workflow"]["pipeline_version"],
            "git_sha": manifest["workflow"]["git_sha"],
        },
        "artifact_set_refs": [
            artifact_set.get("artifact_set_ref")
            for artifact_set in receipt.get("artifact_sets", [])
            if artifact_set.get("artifact_set_ref")
        ],
        "parser_hints": parser_hints,
    }
    return add_manifest_checksum(payload)


def build_multiqc_final_registration(
    *,
    analysis_root: Path,
    html_path: Path,
    multiqc_data_dir: Path,
    stage_manifest: Path,
    parser_relevant_paths: list[Path],
    output_manifest: Path,
    output_receipt: Path,
    output_qeo_manifest: Path,
    metadata: dict[str, Any],
    registration_config: RegistrationConfig,
    generated_at: str | None = None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    generated_at = generated_at or utc_now_iso()
    registration_config.validate()
    require_metadata(
        metadata,
        (
            "analysis_euid",
            "run_euid",
            "pipeline_name",
            "pipeline_version",
            "git_sha",
            "snakemake_version",
            "workflow_config_hash",
            "workflow_profile",
        ),
    )
    required_paths = [html_path, stage_manifest] + [
        multiqc_data_dir / name for name in MULTIQC_REQUIRED_DATA_FILES
    ]
    inventory = collect_inventory(
        analysis_root=analysis_root,
        file_paths=[html_path, stage_manifest] + parser_relevant_paths,
        directory_paths=[multiqc_data_dir],
        required_paths=required_paths,
    )
    manifest = add_manifest_checksum(
        {
            "schema_version": "dayoa.artifact_manifest.v1",
            "manifest_kind": "dayoa.multiqc_final",
            "generated_at": generated_at,
            "producer": {
                "system": registration_config.producer_system,
                "role": "execution_plane",
            },
            "analysis": {
                "analysis_euid": metadata["analysis_euid"],
                "run_euid": metadata["run_euid"],
                "workset_euid": metadata.get("workset_euid", ""),
            },
            "workflow": {
                "pipeline_name": metadata["pipeline_name"],
                "pipeline_version": metadata["pipeline_version"],
                "git_sha": metadata["git_sha"],
                "snakemake_version": metadata["snakemake_version"],
                "workflow_config_hash": metadata["workflow_config_hash"],
                "workflow_profile": metadata["workflow_profile"],
                "container_images": metadata.get("container_images", []),
                "references": metadata.get("references", []),
            },
            "artifact_boundaries": {
                "multiqc_html_is_canonical_data": False,
                "registration_authority": "dewey",
                "qc_interpretation_authority": "r2",
            },
            "root_analysis_dir": {
                "relative_path": ".",
                "registration_required": True,
            },
            "multiqc_data_dir": relative_to_root(multiqc_data_dir, analysis_root),
            "required_files": [relative_to_root(path, analysis_root) for path in required_paths],
            "files": inventory,
            "warnings": parse_stage_manifest_warnings(stage_manifest),
        }
    )
    intents = artifact_intents_for_manifest(
        manifest=manifest,
        analysis_root=analysis_root,
        multiqc_data_dir=multiqc_data_dir,
    )
    receipt = register_artifacts(
        manifest=manifest,
        artifact_intents=intents,
        config=registration_config,
        generated_at=generated_at,
    )
    qeo_manifest = qeo_ingest_manifest(
        manifest=manifest,
        receipt=receipt,
        generated_at=generated_at,
        parser_family="multiqc",
    )
    write_json(output_manifest, manifest)
    write_json(output_receipt, receipt)
    write_json(output_qeo_manifest, qeo_manifest)
    return manifest, receipt, qeo_manifest


def build_analysis_artifact_set_registration(
    *,
    analysis_root: Path,
    input_paths: list[Path],
    output_manifest: Path,
    output_receipt: Path,
    output_qeo_manifest: Path,
    metadata: dict[str, Any],
    registration_config: RegistrationConfig,
    generated_at: str | None = None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    generated_at = generated_at or utc_now_iso()
    registration_config.validate()
    require_metadata(
        metadata,
        (
            "analysis_euid",
            "run_euid",
            "pipeline_name",
            "pipeline_version",
            "git_sha",
            "snakemake_version",
            "workflow_config_hash",
            "workflow_profile",
        ),
    )
    inventory = collect_inventory(
        analysis_root=analysis_root,
        file_paths=input_paths,
        directory_paths=[],
        required_paths=input_paths,
    )
    manifest = add_manifest_checksum(
        {
            "schema_version": "dayoa.artifact_manifest.v1",
            "manifest_kind": "dayoa.analysis_artifact_set",
            "generated_at": generated_at,
            "producer": {
                "system": registration_config.producer_system,
                "role": "execution_plane",
            },
            "analysis": {
                "analysis_euid": metadata["analysis_euid"],
                "run_euid": metadata["run_euid"],
                "workset_euid": metadata.get("workset_euid", ""),
            },
            "workflow": {
                "pipeline_name": metadata["pipeline_name"],
                "pipeline_version": metadata["pipeline_version"],
                "git_sha": metadata["git_sha"],
                "snakemake_version": metadata["snakemake_version"],
                "workflow_config_hash": metadata["workflow_config_hash"],
                "workflow_profile": metadata["workflow_profile"],
                "container_images": metadata.get("container_images", []),
                "references": metadata.get("references", []),
                "input_artifact_refs": metadata.get("input_artifact_refs", []),
            },
            "artifact_layers": {
                "raw_evidence": "preserved",
                "parsed_observations": "qeo",
                "semantic_projections": "qeo_or_downstream",
                "qc_interpretations": "r2",
                "release_decisions": "r2",
            },
            "root_analysis_dir": {
                "relative_path": ".",
                "registration_required": True,
            },
            "files": inventory,
            "failure_artifacts": metadata.get("failure_artifacts", []),
        }
    )
    intents = artifact_intents_for_manifest(
        manifest=manifest,
        analysis_root=analysis_root,
        include_all_files=True,
    )
    receipt = register_artifacts(
        manifest=manifest,
        artifact_intents=intents,
        config=registration_config,
        generated_at=generated_at,
    )
    qeo_manifest = qeo_ingest_manifest(
        manifest=manifest,
        receipt=receipt,
        generated_at=generated_at,
        parser_family="dayoa_analysis_artifact_set",
    )
    write_json(output_manifest, manifest)
    write_json(output_receipt, receipt)
    write_json(output_qeo_manifest, qeo_manifest)
    return manifest, receipt, qeo_manifest


def build_artifact_produced_event(
    *,
    manifest: dict[str, Any],
    receipt: dict[str, Any],
    correlation_id: str,
    occurred_at: str | None = None,
    event_type: str = "lsmc.daylily.artifact.produced.v1",
) -> dict[str, Any]:
    occurred_at = occurred_at or utc_now_iso()
    artifact_set_refs = [
        artifact_set.get("artifact_set_ref")
        for artifact_set in receipt.get("artifact_sets", [])
        if artifact_set.get("artifact_set_ref")
    ]
    payload = {
        "analysis_euid": manifest["analysis"]["analysis_euid"],
        "run_euid": manifest["analysis"]["run_euid"],
        "workset_euid": manifest["analysis"].get("workset_euid", ""),
        "manifest_kind": manifest["manifest_kind"],
        "manifest_checksum": manifest["manifest_checksum"],
        "artifact_set_refs": artifact_set_refs,
        "artifact_count": len(receipt.get("artifacts", [])),
    }
    event_id = "evt_" + stable_sha256_text(
        canonical_json_bytes(
            {
                "event_type": event_type,
                "payload": payload,
                "correlation_id": correlation_id,
            }
        ).decode("utf-8")
    )
    return {
        "event_id": event_id,
        "event_type": event_type,
        "occurred_at": occurred_at,
        "producer": {
            "system": "daylily-omics-analysis",
            "role": "execution_plane",
        },
        "schema_version": "1",
        "payload": payload,
        "correlation_id": correlation_id,
        "causation_id": None,
    }


def _metadata_from_args(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "analysis_euid": args.analysis_euid,
        "run_euid": args.run_euid,
        "workset_euid": args.workset_euid,
        "pipeline_name": args.pipeline_name,
        "pipeline_version": args.pipeline_version,
        "git_sha": args.git_sha,
        "snakemake_version": args.snakemake_version,
        "workflow_config_hash": args.workflow_config_hash,
        "workflow_profile": args.workflow_profile,
        "container_images": args.container_image,
        "references": args.reference,
        "input_artifact_refs": args.input_artifact_ref,
        "failure_artifacts": args.failure_artifact,
    }


def _config_from_args(args: argparse.Namespace) -> RegistrationConfig:
    return RegistrationConfig(
        mode=args.mode,
        dewey_url=args.dewey_url,
        dewey_token=args.dewey_token,
        dewey_token_env=args.dewey_token_env,
        storage_root_uri=args.storage_root_uri,
    )


def _add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--analysis-root", required=True)
    parser.add_argument("--mode", required=True, choices=("local_only", "dewey"))
    parser.add_argument("--dewey-url", default="")
    parser.add_argument("--dewey-token", default="")
    parser.add_argument("--dewey-token-env", default="")
    parser.add_argument("--storage-root-uri", default="")
    parser.add_argument("--analysis-euid", required=True)
    parser.add_argument("--run-euid", required=True)
    parser.add_argument("--workset-euid", default="")
    parser.add_argument("--pipeline-name", required=True)
    parser.add_argument("--pipeline-version", required=True)
    parser.add_argument("--git-sha", required=True)
    parser.add_argument("--snakemake-version", required=True)
    parser.add_argument("--workflow-config-hash", required=True)
    parser.add_argument("--workflow-profile", required=True)
    parser.add_argument("--container-image", action="append", default=[])
    parser.add_argument("--reference", action="append", default=[])
    parser.add_argument("--input-artifact-ref", action="append", default=[])
    parser.add_argument("--failure-artifact", action="append", default=[])
    parser.add_argument("--generated-at", default="")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Register DayOA artifacts for Dewey/QEO.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    multiqc = subparsers.add_parser("multiqc-final")
    _add_common_args(multiqc)
    multiqc.add_argument("--html", required=True)
    multiqc.add_argument("--multiqc-data-dir", required=True)
    multiqc.add_argument("--stage-manifest", required=True)
    multiqc.add_argument("--parser-relevant", action="append", default=[])
    multiqc.add_argument("--artifact-manifest-output", required=True)
    multiqc.add_argument("--dewey-receipt-output", required=True)
    multiqc.add_argument("--qeo-manifest-output", required=True)

    artifact_set = subparsers.add_parser("analysis-artifact-set")
    _add_common_args(artifact_set)
    artifact_set.add_argument("--input-path", action="append", required=True)
    artifact_set.add_argument("--artifact-manifest-output", required=True)
    artifact_set.add_argument("--dewey-receipt-output", required=True)
    artifact_set.add_argument("--qeo-manifest-output", required=True)

    event = subparsers.add_parser("artifact-produced-event")
    event.add_argument("--manifest", required=True)
    event.add_argument("--receipt", required=True)
    event.add_argument("--correlation-id", required=True)
    event.add_argument("--output", required=True)
    event.add_argument("--occurred-at", default="")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    try:
        if args.command == "multiqc-final":
            build_multiqc_final_registration(
                analysis_root=Path(args.analysis_root),
                html_path=Path(args.html),
                multiqc_data_dir=Path(args.multiqc_data_dir),
                stage_manifest=Path(args.stage_manifest),
                parser_relevant_paths=[Path(path) for path in args.parser_relevant],
                output_manifest=Path(args.artifact_manifest_output),
                output_receipt=Path(args.dewey_receipt_output),
                output_qeo_manifest=Path(args.qeo_manifest_output),
                metadata=_metadata_from_args(args),
                registration_config=_config_from_args(args),
                generated_at=args.generated_at or None,
            )
        elif args.command == "analysis-artifact-set":
            build_analysis_artifact_set_registration(
                analysis_root=Path(args.analysis_root),
                input_paths=[Path(path) for path in args.input_path],
                output_manifest=Path(args.artifact_manifest_output),
                output_receipt=Path(args.dewey_receipt_output),
                output_qeo_manifest=Path(args.qeo_manifest_output),
                metadata=_metadata_from_args(args),
                registration_config=_config_from_args(args),
                generated_at=args.generated_at or None,
            )
        elif args.command == "artifact-produced-event":
            manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
            receipt = json.loads(Path(args.receipt).read_text(encoding="utf-8"))
            event = build_artifact_produced_event(
                manifest=manifest,
                receipt=receipt,
                correlation_id=args.correlation_id,
                occurred_at=args.occurred_at or None,
            )
            write_json(Path(args.output), event)
        else:  # pragma: no cover - argparse enforces valid commands.
            raise QeoRegistrationError(f"Unknown command: {args.command}")
    except QeoRegistrationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
