import hashlib
import json
import os
from pathlib import Path


def _evidence_workflow_config_hash():
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


def _evidence_final_parser_relevant_inputs(wildcards):
    return _final_component_inputs(wildcards) + [
        MDIR + "other_reports/rules_benchmark_data_mqc.tsv"
    ]


def _evidence_provenance_refs():
    refs = {
        "pipeline_details_md": "pipeline_details.md",
        "planned_workflow_mmd": "pipeline_workflow_planned.mmd",
        "planned_workflow_pdf": "pipeline_workflow_planned.pdf",
    }
    for key, value in sorted(config.get("dayoa_evidence_provenance_refs", {}).items()):
        refs[str(key)] = str(value)
    return refs


localrules:
    write_dayoa_evidence_manifest,
    produce_dayoa_evidence_manifest,


rule write_dayoa_evidence_manifest:
    input:
        html=MDIR + "reports/DAY_final_multiqc.html",
        data_json=MDIR + "reports/DAY_final_multiqc_data/multiqc_data.json",
        data_general_stats=MDIR + "reports/DAY_final_multiqc_data/multiqc_general_stats.txt",
        data_sources=MDIR + "reports/DAY_final_multiqc_data/multiqc_sources.txt",
        data_log=MDIR + "reports/DAY_final_multiqc_data/multiqc.log",
        stage_manifest=MDIR + "reports/multiqc_inputs/final/manifest.tsv",
        parser_relevant=_evidence_final_parser_relevant_inputs,
    output:
        evidence_manifest=MDIR + "reports/dayoa_evidence_manifest.json",
    log:
        MDIR + "logs/write_dayoa_evidence_manifest.log"
    params:
        multiqc_data_dir=MDIR + "reports/DAY_final_multiqc_data",
        cluster_sample="write_dayoa_evidence_manifest",
    container: None
    run:
        from daylily_omics_analysis.evidence_manifest import (
            EvidenceMetadata,
            build_multiqc_final_evidence_manifest,
            snakemake_version,
        )

        metadata = EvidenceMetadata(
            analysis_name=Path(".").resolve().name,
            run_name=str(config.get("run_name", "")).strip(),
            genome_build=str(config.get("genome_build", "")).strip(),
            pipeline_name="daylily-omics-analysis",
            pipeline_version=str(config.get("gittag", "")).strip(),
            git_sha=str(config.get("githash", "")).strip(),
            snakemake_version=snakemake_version(),
            workflow_config_hash=_evidence_workflow_config_hash(),
            workflow_profile=os.environ.get("DAY_PROFILE", ""),
            container_images=(),
            references=(str(config.get("genome_build", "")).strip(),),
            provenance_refs=_evidence_provenance_refs(),
        )
        build_multiqc_final_evidence_manifest(
            analysis_root=Path("."),
            html_path=Path(input.html),
            multiqc_data_dir=Path(params.multiqc_data_dir),
            stage_manifest=Path(input.stage_manifest),
            parser_relevant_paths=[Path(path) for path in input.parser_relevant],
            output_manifest=Path(output.evidence_manifest),
            metadata=metadata,
        )


rule produce_dayoa_evidence_manifest:
    input:
        MDIR + "reports/dayoa_evidence_manifest.json",
    log:
        MDIR + "logs/produce_dayoa_evidence_manifest.log"
    benchmark:
        "logs/benchmarks/produce_dayoa_evidence_manifest.bench.tsv"
