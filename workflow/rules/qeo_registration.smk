import hashlib
import json
import os
from pathlib import Path

from snakemake.exceptions import WorkflowError


def _qeo_registration_config():
    cfg = config.get("qeo_registration")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "QEO registration requires explicit qeo_registration config with mode "
            "'local_only' or 'dewey'."
        )
    return cfg


def _qeo_config_value(key, *, required=False):
    cfg = _qeo_registration_config()
    value = str(cfg.get(key, "")).strip()
    if required and not value:
        raise WorkflowError(f"QEO registration config is missing qeo_registration.{key}.")
    return value


def _qeo_workflow_config_hash():
    material = {
        "genome_build": config.get("genome_build", ""),
        "profile": os.environ.get("DAY_PROFILE", ""),
        "multiqc_qc": config.get("multiqc_qc", {}),
        "samples_table_path": samples_table_path,
        "units_table_path": units_table_path,
    }
    return hashlib.sha256(
        json.dumps(material, sort_keys=True, default=str).encode("utf-8")
    ).hexdigest()


def _qeo_metadata():
    cfg = _qeo_registration_config()
    return {
        "analysis_euid": str(cfg.get("analysis_euid", "")).strip(),
        "run_euid": str(cfg.get("run_euid", "")).strip(),
        "workset_euid": str(cfg.get("workset_euid", "")).strip(),
        "pipeline_name": "daylily-omics-analysis",
        "pipeline_version": str(config.get("gittag", "")).strip(),
        "git_sha": str(config.get("githash", "")).strip(),
        "snakemake_version": str(cfg.get("snakemake_version", "")).strip(),
        "workflow_config_hash": _qeo_workflow_config_hash(),
        "workflow_profile": os.environ.get("DAY_PROFILE", ""),
        "container_images": ["docker://multiqc/multiqc:v1.35"],
        "references": [str(config.get("genome_build", "")).strip()],
    }


def _qeo_registration_settings():
    return {
        "mode": _qeo_config_value("mode", required=True),
        "dewey_url": _qeo_config_value("dewey_url"),
        "dewey_token": _qeo_config_value("dewey_token"),
        "dewey_token_env": _qeo_config_value("dewey_token_env"),
        "storage_root_uri": _qeo_config_value("storage_root_uri"),
    }


def _qeo_final_parser_relevant_inputs(wildcards):
    return _final_component_inputs(wildcards) + [
        MDIR + "other_reports/rules_benchmark_data_mqc.tsv"
    ]


localrules:
    register_multiqc_final,
    register_analysis_artifact_set,
    publish_qeo_ingest_event,
    produce_qeo_multiqc_registration,
    produce_qeo_analysis_artifact_set,
    produce_qeo_ingest_event,


rule register_multiqc_final:
    input:
        html=MDIR + "reports/DAY_final_multiqc.html",
        data_json=MDIR + "reports/DAY_final_multiqc_data/multiqc_data.json",
        data_general_stats=MDIR + "reports/DAY_final_multiqc_data/multiqc_general_stats.txt",
        data_sources=MDIR + "reports/DAY_final_multiqc_data/multiqc_sources.txt",
        data_log=MDIR + "reports/DAY_final_multiqc_data/multiqc.log",
        stage_manifest=MDIR + "reports/multiqc_inputs/final/manifest.tsv",
        parser_relevant=_qeo_final_parser_relevant_inputs,
    output:
        artifact_manifest=MDIR + "reports/DAY_final_multiqc.artifact_manifest.json",
        dewey_receipt=MDIR + "reports/DAY_final_multiqc.dewey_receipt.json",
        qeo_manifest=MDIR + "reports/DAY_final_multiqc.qeo_manifest.json",
    params:
        multiqc_data_dir=MDIR + "reports/DAY_final_multiqc_data",
        cluster_sample="register_multiqc_final",
    container: None
    run:
        from daylily_omics_analysis.qeo_registration import (
            RegistrationConfig,
            build_multiqc_final_registration,
        )

        settings = _qeo_registration_settings()
        build_multiqc_final_registration(
            analysis_root=Path("."),
            html_path=Path(input.html),
            multiqc_data_dir=Path(params.multiqc_data_dir),
            stage_manifest=Path(input.stage_manifest),
            parser_relevant_paths=[Path(path) for path in input.parser_relevant],
            output_manifest=Path(output.artifact_manifest),
            output_receipt=Path(output.dewey_receipt),
            output_qeo_manifest=Path(output.qeo_manifest),
            metadata=_qeo_metadata(),
            registration_config=RegistrationConfig(**settings),
        )


rule register_analysis_artifact_set:
    input:
        multiqc_manifest=MDIR + "reports/DAY_final_multiqc.artifact_manifest.json",
        multiqc_receipt=MDIR + "reports/DAY_final_multiqc.dewey_receipt.json",
        multiqc_qeo_manifest=MDIR + "reports/DAY_final_multiqc.qeo_manifest.json",
        final_html=MDIR + "reports/DAY_final_multiqc.html",
        final_original_html=MDIR + "reports/DAY_final_multiqc.original.html",
        final_data_json=MDIR + "reports/DAY_final_multiqc_data/multiqc_data.json",
        final_general_stats=MDIR + "reports/DAY_final_multiqc_data/multiqc_general_stats.txt",
        final_sources=MDIR + "reports/DAY_final_multiqc_data/multiqc_sources.txt",
        final_multiqc_log=MDIR + "reports/DAY_final_multiqc_data/multiqc.log",
        stage_manifest=MDIR + "reports/multiqc_inputs/final/manifest.tsv",
        benchmark_mqc=MDIR + "other_reports/rules_benchmark_data_mqc.tsv",
        benchmark_summary=MDIR + "reports/benchmarks_summary.tsv",
        final_log=MDIR + "reports/logs/all__mqc_fin_a.log",
    output:
        artifact_manifest=MDIR + "reports/analysis_artifact_set.manifest.json",
        dewey_receipt=MDIR + "reports/analysis_artifact_set.dewey_receipt.json",
        qeo_manifest=MDIR + "reports/analysis_artifact_set.qeo_ingest_manifest.json",
    params:
        cluster_sample="register_analysis_artifact_set",
    container: None
    run:
        from daylily_omics_analysis.qeo_registration import (
            RegistrationConfig,
            build_analysis_artifact_set_registration,
        )

        settings = _qeo_registration_settings()
        build_analysis_artifact_set_registration(
            analysis_root=Path("."),
            input_paths=[Path(path) for path in input],
            output_manifest=Path(output.artifact_manifest),
            output_receipt=Path(output.dewey_receipt),
            output_qeo_manifest=Path(output.qeo_manifest),
            metadata=_qeo_metadata(),
            registration_config=RegistrationConfig(**settings),
        )


rule publish_qeo_ingest_event:
    input:
        manifest=MDIR + "reports/analysis_artifact_set.manifest.json",
        receipt=MDIR + "reports/analysis_artifact_set.dewey_receipt.json",
    output:
        event=MDIR + "reports/qeo/outbox/lsmc.daylily.artifact.produced.v1.json",
    params:
        cluster_sample="publish_qeo_ingest_event",
    container: None
    run:
        import json
        from daylily_omics_analysis.qeo_registration import (
            build_artifact_produced_event,
            write_json,
        )

        manifest = json.loads(Path(input.manifest).read_text(encoding="utf-8"))
        receipt = json.loads(Path(input.receipt).read_text(encoding="utf-8"))
        event = build_artifact_produced_event(
            manifest=manifest,
            receipt=receipt,
            correlation_id=manifest["manifest_checksum"],
        )
        write_json(Path(output.event), event)


rule produce_qeo_multiqc_registration:
    input:
        MDIR + "reports/DAY_final_multiqc.artifact_manifest.json",
        MDIR + "reports/DAY_final_multiqc.dewey_receipt.json",
        MDIR + "reports/DAY_final_multiqc.qeo_manifest.json",


rule produce_qeo_analysis_artifact_set:
    input:
        MDIR + "reports/analysis_artifact_set.manifest.json",
        MDIR + "reports/analysis_artifact_set.dewey_receipt.json",
        MDIR + "reports/analysis_artifact_set.qeo_ingest_manifest.json",


rule produce_qeo_ingest_event:
    input:
        MDIR + "reports/qeo/outbox/lsmc.daylily.artifact.produced.v1.json",
