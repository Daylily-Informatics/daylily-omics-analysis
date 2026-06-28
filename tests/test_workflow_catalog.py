from __future__ import annotations

from daylily_omics_analysis import WorkflowCatalogError
from daylily_omics_analysis.workflow_catalog import (
    _normalize_option_value,
    _render_option_value,
    _validate_catalog,
    load_workflow_catalog,
    render_workflow_command,
)

KITCHEN_SINK_TARGETS = [
    "produce_all_align",
    "produce_all_dedup_cram",
    "produce_all_snv_vcf",
    "produce_all_sv_vcf",
    "produce_alignstats",
    "produce_snv_concordances",
    "produce_relatedness",
    "produce_vep",
    "produce_htd_calls",
    "produce_expansionhunter",
    "longtr_all",
    "longtr_diseaser",
    "produce_metagenomics",
    "produce_multiqc_all",
    "produce_dayoa_evidence_manifest",
]


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
    assert preview["summary"]["targets"] == KITCHEN_SINK_TARGETS
    assert preview["argv"][:3] == [
        "dy-r",
        "produce_all_align",
        "produce_all_dedup_cram",
    ]
    assert "-j" in preview["argv"]
    assert "genome_build=hg38" in preview["argv"]
    argv_text = " ".join(preview["argv"])
    assert "multiqc_qc=" in argv_text
    assert "enable_long_running" in argv_text
    assert "aligners=['strobe','bwa2a','sent']" in preview["argv"]
    assert "dedupers=['dmd']" in preview["argv"]
    assert "snv_callers=['oct','sentd','deep19']" in preview["argv"]
    assert "sv_callers=['tiddit','manta','dysgu']" in preview["argv"]
    assert "htd_callers=['cyrius']" in preview["argv"]
    assert preview["shell_preview"].startswith(
        "source dyoainit && dy-a slurm hg38 && dy-r "
    )


def test_workflow_catalog_exposes_smn12_orthogonal_htd_choices() -> None:
    catalog = load_workflow_catalog()
    kitchensink = next(
        workflow
        for workflow in catalog["workflows"]
        if workflow["workflow_id"] == "germline_wgs_kitchensink"
    )
    htd_option = next(
        option for option in kitchensink["options"] if option["option_id"] == "htd_callers"
    )

    assert htd_option["default"] == ["cyrius"]
    assert [choice["value"] for choice in htd_option["choices"]] == [
        "gauchian",
        "cyrius",
        "smn12",
        "smaca",
        "sma_finder",
        "hapsma",
    ]

    preview = render_workflow_command(
        workflow_id="germline_wgs_kitchensink",
        genome_build="hg38",
        execution_profile="slurm",
        options={
            "htd_callers": ["gauchian", "cyrius", "smn12", "smaca", "sma_finder", "hapsma"],
        },
        input_context={"provided_inputs": ["workset_manifest"], "sample_count": 1},
    )

    assert preview["valid"] is True
    assert "htd_callers=['gauchian','cyrius','smn12','smaca','sma_finder','hapsma']" in preview["argv"]


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


def test_render_workflow_command_reports_validation_errors_and_warnings() -> None:
    preview = render_workflow_command(
        workflow_id="germline_wgs_snv",
        genome_build="b37",
        execution_profile="aws",
        options={
            "unknown": True,
            "jobs": 999,
            "aligners": ["bad-aligner"],
            "dedupers": [],
            "snv_callers": [],
        },
        input_context={"provided_inputs": ["workset_manifest"], "sample_count": 0},
    )

    assert preview["valid"] is False
    assert preview["argv"] == []
    assert preview["shell_preview"] == ""
    assert preview["warnings"] == [
        "No sample rows were detected from the current manifest selection."
    ]
    assert any(
        "Genome build 'b37' is not supported" in error
        for error in preview["validation_errors"]
    )
    assert any(
        "Execution profile 'aws' is not supported" in error
        for error in preview["validation_errors"]
    )
    assert "Unknown workflow option 'unknown'." in preview["validation_errors"]
    assert "Parallel jobs must be at most 500." in preview["validation_errors"]
    assert (
        "Aligners contains unsupported value 'bad-aligner'."
        in preview["validation_errors"]
    )
    assert "Dedupers requires at least one value." in preview["validation_errors"]
    assert "SNV callers requires at least one value." in preview["validation_errors"]


def test_render_workflow_command_accepts_string_option_values() -> None:
    preview = render_workflow_command(
        workflow_id="germline_wgs_snv",
        genome_build="hg38",
        execution_profile="local",
        options={
            "print_commands": "off",
            "keep_going": "on",
            "jobs": "2",
            "aligners": "sent",
            "dedupers": ["dmd", "dmd"],
            "snv_callers": ["sentd", ""],
        },
        input_context={
            "provided_inputs": ["workset_manifest", "workset_manifest"],
            "sample_count": -5,
        },
    )

    assert preview["valid"] is True
    assert "-p" not in preview["argv"]
    assert "-k" in preview["argv"]
    assert "-j" in preview["argv"]
    assert preview["normalized_spec"]["options"]["jobs"] == 2
    assert preview["normalized_spec"]["options"]["aligners"] == ["sent"]
    assert preview["normalized_spec"]["options"]["dedupers"] == ["dmd"]
    assert preview["normalized_spec"]["options"]["snv_callers"] == ["sentd"]
    assert preview["normalized_spec"]["input_context"]["sample_count"] == 0
    assert preview["warnings"] == [
        "No sample rows were detected from the current manifest selection."
    ]


def test_workflow_catalog_private_validation_guards() -> None:
    for payload, expected in (
        ([], "Workflow catalog must be a JSON object."),
        ({}, "Workflow catalog is missing 'schema_version'."),
        (
            {
                "schema_version": "1",
                "catalog_version": "1",
                "repository": "repo",
                "display_name": "Repo",
                "workflows": [],
            },
            "Workflow catalog must include at least one workflow.",
        ),
        (
            {
                "schema_version": "1",
                "catalog_version": "1",
                "repository": "repo",
                "display_name": "Repo",
                "workflows": [{"workflow_id": ""}],
            },
            "Each workflow requires a workflow_id.",
        ),
        (
            {
                "schema_version": "1",
                "catalog_version": "1",
                "repository": "repo",
                "display_name": "Repo",
                "workflows": [
                    {
                        "workflow_id": "bad_fixed_config",
                        "display_name": "Bad Fixed Config",
                        "description": "Bad fixed config",
                        "targets": ["target"],
                        "fixed_config": [""],
                        "supported_genome_builds": ["hg38"],
                        "supported_execution_profiles": ["local"],
                        "required_inputs": [],
                        "options": [],
                    }
                ],
            },
            "fixed_config must be a list of non-empty strings",
        ),
    ):
        try:
            _validate_catalog(payload)
        except WorkflowCatalogError as exc:
            assert expected in str(exc)
        else:  # pragma: no cover - defensive
            raise AssertionError("expected WorkflowCatalogError")


def test_option_normalizers_cover_scalar_enum_and_renderer_errors() -> None:
    enum_option = {
        "option_id": "caller",
        "label": "Caller",
        "type": "enum",
        "choices": [{"value": "sentd"}, {"value": "oct"}],
    }
    assert _normalize_option_value(enum_option, " sentd ") == "sentd"

    for option, value, expected in (
        (
            {"option_id": "enabled", "label": "Enabled", "type": "boolean"},
            "maybe",
            "Enabled must be true or false.",
        ),
        (
            {"option_id": "jobs", "label": "Jobs", "type": "integer"},
            "two",
            "Jobs must be an integer.",
        ),
        (
            {"option_id": "jobs", "label": "Jobs", "type": "integer", "minimum": 2},
            1,
            "Jobs must be at least 2.",
        ),
        (enum_option, "bad", "Caller must be one of: oct, sentd."),
        (
            {"option_id": "callers", "label": "Callers", "type": "multi_enum"},
            object(),
            "Callers must be a list of values.",
        ),
        (
            {"option_id": "mode", "label": "Mode", "type": "unknown"},
            "x",
            "Mode uses unsupported type 'unknown'.",
        ),
    ):
        try:
            _normalize_option_value(option, value)
        except WorkflowCatalogError as exc:
            assert expected in str(exc)
        else:  # pragma: no cover - defensive
            raise AssertionError("expected WorkflowCatalogError")

    assert (
        _render_option_value(
            {"option_id": "profile", "render_as": "config_scalar"}, "slurm"
        )
        == "profile=slurm"
    )
    try:
        _render_option_value({"option_id": "profile", "render_as": "unknown"}, "slurm")
    except WorkflowCatalogError as exc:
        assert "Unsupported render_as 'unknown' for option 'profile'." in str(exc)
    else:  # pragma: no cover - defensive
        raise AssertionError("expected WorkflowCatalogError")
