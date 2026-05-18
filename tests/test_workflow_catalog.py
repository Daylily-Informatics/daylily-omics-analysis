from __future__ import annotations

from daylily_omics_analysis import WorkflowCatalogError
from daylily_omics_analysis.workflow_catalog import load_workflow_catalog, render_workflow_command


def test_augment_wrapper_does_not_pass_workflow_args_to_dyoainit() -> None:
    wrapper = open("bin/augment_setup_and_run_dayoa.bash", encoding="utf-8").read()

    assert '_DYOA_WRAPPER_POSITIONAL_ARGS=("$@")' in wrapper
    assert "set --\nsource dyoainit" in wrapper
    assert 'set -- "${_DYOA_WRAPPER_POSITIONAL_ARGS[@]}"' in wrapper
    assert 'source bin/day_activate "$LOCAL_OR_SLURM" "$GENOME_CODE"' in wrapper


def test_catalog_exposes_expected_workflows() -> None:
    catalog = load_workflow_catalog()

    assert catalog["repository"] == "daylily-omics-analysis"
    assert catalog["catalog_version"] == "1.0.0"
    assert [workflow["workflow_id"] for workflow in catalog["workflows"]] == [
        "test_help",
        "germline_wgs_snv",
        "germline_wgs_snv_sv",
        "germline_wgs_kitchensink",
    ]


def test_render_workflow_command_normalizes_and_renders_kitchensink() -> None:
    preview = render_workflow_command(
        workflow_id="germline_wgs_kitchensink",
        genome_build="hg38",
        execution_profile="slurm",
        options={
            "jobs": 24,
            "aligners": ["strobe", "bwa2a", "sent"],
            "dedupers": ["dmd"],
            "snv_callers": ["oct", "sentd", "deep19"],
            "print_commands": True,
            "keep_going": True,
        },
        input_context={"provided_inputs": ["workset_manifest"], "sample_count": 8},
    )

    assert preview["valid"] is True
    assert preview["validation_errors"] == []
    assert preview["summary"]["targets"] == [
        "produce_alignstats",
        "produce_snv_concordances",
        "produce_manta_sv_vcf",
        "produce_tiddit_sv_vcf",
        "produce_dysgu_sv_vcf",
        "produce_multiqc_all",
    ]
    assert preview["argv"][:3] == ["dy-r", "produce_alignstats", "produce_snv_concordances"]
    assert "-j" in preview["argv"]
    assert "genome_build=hg38" in preview["argv"]
    assert "aligners=['strobe','bwa2a','sent']" in preview["argv"]
    assert "dedupers=['dmd']" in preview["argv"]
    assert preview["shell_preview"].startswith("source dyoainit && dy-a slurm hg38 && dy-r ")


def test_render_workflow_command_rejects_missing_required_input() -> None:
    preview = render_workflow_command(
        workflow_id="germline_wgs_snv",
        genome_build="hg38",
        execution_profile="slurm",
        options={},
        input_context={"provided_inputs": [], "sample_count": 0},
    )

    assert preview["valid"] is False
    assert "Workset manifest is required" in preview["validation_errors"][0]
    assert preview["argv"] == []


def test_render_workflow_command_rejects_unknown_workflow() -> None:
    try:
        render_workflow_command(
            workflow_id="not-real",
            genome_build="hg38",
            execution_profile="slurm",
            options={},
            input_context={"provided_inputs": ["workset_manifest"], "sample_count": 1},
        )
    except WorkflowCatalogError as exc:
        assert "Unknown workflow_id 'not-real'" in str(exc)
    else:  # pragma: no cover - defensive
        raise AssertionError("expected WorkflowCatalogError")
