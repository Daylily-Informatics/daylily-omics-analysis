from __future__ import annotations

import copy
import json
import shlex
from importlib import resources
from typing import Any


class WorkflowCatalogError(ValueError):
    """Raised when the packaged workflow catalog is invalid or a request cannot be rendered."""


_CATALOG_RESOURCE = "data/workflow_catalog.v1.json"
_OPTION_TYPES = {"boolean", "integer", "enum", "multi_enum"}
_OPTION_RENDERERS = {"flag", "arg", "config_scalar", "config_list", "none"}


def load_workflow_catalog() -> dict[str, Any]:
    resource = resources.files("daylily_omics_analysis").joinpath(_CATALOG_RESOURCE)
    payload = json.loads(resource.read_text(encoding="utf-8"))
    _validate_catalog(payload)
    return copy.deepcopy(payload)


def render_workflow_command(
    *,
    workflow_id: str,
    genome_build: str,
    execution_profile: str,
    options: dict[str, Any] | None = None,
    input_context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    catalog = load_workflow_catalog()
    workflow = _workflow_by_id(catalog, workflow_id)
    normalized_options: dict[str, Any] = {}
    errors: list[str] = []
    warnings: list[str] = []

    normalized_genome_build = str(genome_build or "").strip()
    if normalized_genome_build not in workflow["supported_genome_builds"]:
        errors.append(
            f"Genome build '{normalized_genome_build}' is not supported by {workflow['display_name']}."
        )

    normalized_execution_profile = str(execution_profile or "").strip()
    if normalized_execution_profile not in workflow["supported_execution_profiles"]:
        errors.append(
            "Execution profile "
            f"'{normalized_execution_profile}' is not supported by {workflow['display_name']}."
        )

    raw_options = dict(options or {})
    declared_option_ids = {str(option["option_id"]) for option in workflow["options"]}
    unknown_option_ids = sorted(set(raw_options) - declared_option_ids)
    if unknown_option_ids:
        errors.extend(
            [f"Unknown workflow option '{option_id}'." for option_id in unknown_option_ids]
        )

    for option in workflow["options"]:
        option_id = str(option["option_id"])
        raw_value = raw_options.get(option_id, option.get("default"))
        try:
            normalized_options[option_id] = _normalize_option_value(option, raw_value)
        except WorkflowCatalogError as exc:
            errors.append(str(exc))

    normalized_input_context = _normalize_input_context(input_context)
    provided_inputs = set(normalized_input_context["provided_inputs"])
    for required_input in workflow["required_inputs"]:
        if required_input.get("required", True) and required_input["input_id"] not in provided_inputs:
            errors.append(f"{required_input['label']} is required for {workflow['display_name']}.")

    if "workset_manifest" in provided_inputs and normalized_input_context["sample_count"] <= 0:
        warnings.append("No sample rows were detected from the current manifest selection.")

    shell_preview = ""
    argv: list[str] = []
    if not errors:
        argv = _render_argv(
            workflow=workflow,
            genome_build=normalized_genome_build,
            options=normalized_options,
        )
        shell_preview = (
            f"source dyoainit && dy-a {normalized_execution_profile} {normalized_genome_build} && "
            f"{shlex.join(argv)}"
        )

    return {
        "valid": not errors,
        "repository": str(catalog["repository"]),
        "catalog_version": str(catalog["catalog_version"]),
        "workflow_id": str(workflow["workflow_id"]),
        "display_name": str(workflow["display_name"]),
        "argv": argv,
        "shell_preview": shell_preview,
        "summary": {
            "pipeline_type": str(workflow["display_name"]),
            "workflow_id": str(workflow["workflow_id"]),
            "description": str(workflow["description"]),
            "genome_build": normalized_genome_build,
            "execution_profile": normalized_execution_profile,
            "targets": _render_targets(workflow=workflow, options=normalized_options),
            "sample_count": normalized_input_context["sample_count"],
            "input_mode": normalized_input_context["input_mode"],
            "required_inputs": copy.deepcopy(workflow["required_inputs"]),
        },
        "normalized_spec": {
            "workflow_id": str(workflow["workflow_id"]),
            "genome_build": normalized_genome_build,
            "execution_profile": normalized_execution_profile,
            "options": normalized_options,
            "input_context": normalized_input_context,
        },
        "validation_errors": errors,
        "warnings": warnings,
    }


def _validate_catalog(payload: dict[str, Any]) -> None:
    if not isinstance(payload, dict):
        raise WorkflowCatalogError("Workflow catalog must be a JSON object.")
    for field_name in ("schema_version", "catalog_version", "repository", "display_name"):
        if not str(payload.get(field_name) or "").strip():
            raise WorkflowCatalogError(f"Workflow catalog is missing '{field_name}'.")
    workflows = payload.get("workflows")
    if not isinstance(workflows, list) or not workflows:
        raise WorkflowCatalogError("Workflow catalog must include at least one workflow.")
    seen_workflows: set[str] = set()
    for workflow in workflows:
        workflow_id = str(workflow.get("workflow_id") or "").strip()
        if not workflow_id:
            raise WorkflowCatalogError("Each workflow requires a workflow_id.")
        if workflow_id in seen_workflows:
            raise WorkflowCatalogError(f"Duplicate workflow_id '{workflow_id}' in catalog.")
        seen_workflows.add(workflow_id)
        if not str(workflow.get("display_name") or "").strip():
            raise WorkflowCatalogError(f"Workflow '{workflow_id}' is missing display_name.")
        if not isinstance(workflow.get("targets"), list) or not workflow["targets"]:
            raise WorkflowCatalogError(f"Workflow '{workflow_id}' must declare targets.")
        if not isinstance(workflow.get("supported_genome_builds"), list) or not workflow[
            "supported_genome_builds"
        ]:
            raise WorkflowCatalogError(
                f"Workflow '{workflow_id}' must declare supported_genome_builds."
            )
        if not isinstance(workflow.get("supported_execution_profiles"), list) or not workflow[
            "supported_execution_profiles"
        ]:
            raise WorkflowCatalogError(
                f"Workflow '{workflow_id}' must declare supported_execution_profiles."
            )
        option_ids: set[str] = set()
        for option in list(workflow.get("options") or []):
            option_id = str(option.get("option_id") or "").strip()
            if not option_id:
                raise WorkflowCatalogError(f"Workflow '{workflow_id}' has an option without option_id.")
            if option_id in option_ids:
                raise WorkflowCatalogError(
                    f"Workflow '{workflow_id}' defines option '{option_id}' more than once."
                )
            option_ids.add(option_id)
            if str(option.get("type") or "").strip() not in _OPTION_TYPES:
                raise WorkflowCatalogError(
                    f"Workflow '{workflow_id}' option '{option_id}' has unsupported type."
                )
            if str(option.get("render_as") or "").strip() not in _OPTION_RENDERERS:
                raise WorkflowCatalogError(
                    f"Workflow '{workflow_id}' option '{option_id}' has unsupported render_as."
                )


def _workflow_by_id(catalog: dict[str, Any], workflow_id: str) -> dict[str, Any]:
    normalized_workflow_id = str(workflow_id or "").strip()
    for workflow in list(catalog.get("workflows") or []):
        if str(workflow.get("workflow_id") or "").strip() == normalized_workflow_id:
            return workflow
    raise WorkflowCatalogError(f"Unknown workflow_id '{normalized_workflow_id}'.")


def _normalize_option_value(option: dict[str, Any], raw_value: Any) -> Any:
    option_id = str(option["option_id"])
    option_type = str(option["type"])
    label = str(option.get("label") or option_id)
    if option_type == "boolean":
        if isinstance(raw_value, bool):
            return raw_value
        if isinstance(raw_value, str):
            lowered = raw_value.strip().lower()
            if lowered in {"true", "1", "yes", "on"}:
                return True
            if lowered in {"false", "0", "no", "off", ""}:
                return False
        if raw_value in (0, 1):
            return bool(raw_value)
        raise WorkflowCatalogError(f"{label} must be true or false.")

    if option_type == "integer":
        try:
            normalized = int(raw_value)
        except (TypeError, ValueError) as exc:
            raise WorkflowCatalogError(f"{label} must be an integer.") from exc
        minimum = option.get("minimum")
        maximum = option.get("maximum")
        if minimum is not None and normalized < int(minimum):
            raise WorkflowCatalogError(f"{label} must be at least {minimum}.")
        if maximum is not None and normalized > int(maximum):
            raise WorkflowCatalogError(f"{label} must be at most {maximum}.")
        return normalized

    if option_type == "enum":
        normalized = str(raw_value or "").strip()
        allowed = {str(choice["value"]) for choice in list(option.get("choices") or [])}
        if normalized not in allowed:
            raise WorkflowCatalogError(f"{label} must be one of: {', '.join(sorted(allowed))}.")
        return normalized

    if option_type == "multi_enum":
        if isinstance(raw_value, str):
            values = [raw_value]
        elif isinstance(raw_value, list):
            values = raw_value
        else:
            raise WorkflowCatalogError(f"{label} must be a list of values.")
        normalized_values: list[str] = []
        allowed = {str(choice["value"]) for choice in list(option.get("choices") or [])}
        retired = {
            str(choice["value"]): str(choice.get("message") or f"{label} value is retired.")
            for choice in list(option.get("retired_values") or [])
        }
        for item in values:
            normalized = str(item or "").strip()
            if not normalized:
                continue
            if normalized in retired:
                raise WorkflowCatalogError(retired[normalized])
            if normalized not in allowed:
                raise WorkflowCatalogError(f"{label} contains unsupported value '{normalized}'.")
            if normalized not in normalized_values:
                normalized_values.append(normalized)
        if option.get("required", False) and not normalized_values:
            raise WorkflowCatalogError(f"{label} requires at least one value.")
        return normalized_values

    raise WorkflowCatalogError(f"{label} uses unsupported type '{option_type}'.")


def _normalize_input_context(input_context: dict[str, Any] | None) -> dict[str, Any]:
    payload = dict(input_context or {})
    provided_inputs: list[str] = []
    for item in list(payload.get("provided_inputs") or []):
        normalized = str(item or "").strip()
        if normalized and normalized not in provided_inputs:
            provided_inputs.append(normalized)
    sample_count = int(payload.get("sample_count") or 0)
    input_mode = str(payload.get("input_mode") or ("none" if not provided_inputs else "workset_manifest"))
    return {
        "provided_inputs": provided_inputs,
        "sample_count": max(sample_count, 0),
        "input_mode": input_mode,
    }


def _render_targets(*, workflow: dict[str, Any], options: dict[str, Any]) -> list[str]:
    targets: list[str] = [str(target) for target in workflow["targets"]]
    target_groups = dict(workflow.get("target_groups") or {})
    for option in workflow["options"]:
        if str(option.get("render_as") or "") != "none":
            continue
        option_id = str(option["option_id"])
        if not bool(options.get(option_id)):
            continue
        targets.extend(str(target) for target in list(target_groups.get(option_id) or []))
    deduped: list[str] = []
    for target in targets:
        if target not in deduped:
            deduped.append(target)
    return deduped


def _render_argv(*, workflow: dict[str, Any], genome_build: str, options: dict[str, Any]) -> list[str]:
    argv = ["dy-r", *_render_targets(workflow=workflow, options=options)]
    config_parts = [f"genome_build={genome_build}"]
    for option in workflow["options"]:
        option_id = str(option["option_id"])
        render_as = str(option["render_as"])
        rendered = _render_option_value(option, options.get(option_id))
        if not rendered:
            continue
        if render_as == "flag":
            argv.append(rendered)
        elif render_as == "arg":
            argv.extend(rendered.split(" ", 1))
        elif render_as in {"config_scalar", "config_list"}:
            config_parts.append(rendered)
    if config_parts:
        argv.extend(["--config", *config_parts])
    return argv


def _render_option_value(option: dict[str, Any], value: Any) -> str:
    option_id = str(option["option_id"])
    render_as = str(option["render_as"])
    if render_as == "none":
        return ""
    if render_as == "flag":
        return str(option.get("flag") or "") if bool(value) else ""
    if render_as == "arg":
        flag = str(option.get("flag") or "").strip()
        return f"{flag} {value}" if flag else str(value)
    if render_as == "config_scalar":
        return f"{option_id}={value}"
    if render_as == "config_list":
        joined = ",".join(f"'{item}'" for item in list(value or []))
        return f"{option_id}=[{joined}]"
    raise WorkflowCatalogError(f"Unsupported render_as '{render_as}' for option '{option_id}'.")
