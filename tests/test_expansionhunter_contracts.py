from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path
from types import ModuleType

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
CATALOG_NAME = "STRchive-disease-loci.hg38.stranger.json"
EXPECTED_CATALOG_PATH = REPO_ROOT / "resources" / "strchive" / CATALOG_NAME
EXPANSIONHUNTER_RULE = REPO_ROOT / "workflow" / "rules" / "expansionhunter.smk"
PARSER_PATH = REPO_ROOT / "bin" / "util" / "parse_expansionhunter_json.py"


def _read_text(path: Path) -> str:
    assert path.exists(), f"Missing expected file: {path.relative_to(REPO_ROOT)}"
    return path.read_text(encoding="utf-8")


def _load_yaml(path: Path) -> dict:
    assert path.exists(), f"Missing expected file: {path.relative_to(REPO_ROOT)}"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _load_module(path: Path, module_name: str) -> ModuleType:
    assert path.exists(), f"Missing expected file: {path.relative_to(REPO_ROOT)}"
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"Unable to import {path.relative_to(REPO_ROOT)}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _coerce_rows(result: object) -> list[dict[str, object]]:
    if isinstance(result, tuple):
        result = result[0]
    if isinstance(result, list):
        return result
    if hasattr(result, "to_dict"):
        return result.to_dict("records")
    return list(result)  # type: ignore[arg-type]


def _call_parser(
    module: ModuleType,
    json_path: Path,
    catalog_path: Path,
    *,
    sample: str = "HG002",
    aligner: str = "sent",
    deduper: str = "dmd",
) -> list[dict[str, object]]:
    if all(
        hasattr(module, name)
        for name in ("load_json", "build_catalog_by_locus", "get_sample_id", "build_rows")
    ):
        eh_data = module.load_json(json_path, "ExpansionHunter")
        catalog = module.load_json(catalog_path, "STRchive catalog")
        catalog_by_locus = module.build_catalog_by_locus(catalog)
        sample_id = module.get_sample_id(eh_data, json_path, sample)
        return _coerce_rows(
            module.build_rows(eh_data, catalog_by_locus, sample_id, aligner, deduper)
        )

    for name in (
        "parse_expansionhunter_json",
        "parse_expansionhunter_results",
        "parse_expansionhunter",
        "parse_json",
        "parse",
    ):
        parser = getattr(module, name, None)
        if parser is None:
            continue
        try:
            return _coerce_rows(
                parser(
                    json_path,
                    catalog_path,
                    sample=sample,
                    aligner=aligner,
                    deduper=deduper,
                )
            )
        except TypeError:
            return _coerce_rows(parser(json_path, catalog_path, sample, aligner, deduper))
    raise AssertionError("Parser module must expose a parse function or build_rows helpers.")


def _row_by_locus(rows: list[dict[str, object]], locus: str) -> dict[str, object]:
    matches = [
        row
        for row in rows
        if row.get("locus_id") == locus
        or row.get("locus") == locus
        or row.get("variant_id") == locus
    ]
    assert len(matches) == 1, f"Expected one parsed row for {locus}, got {matches}"
    return matches[0]


def _status(row: dict[str, object]) -> str:
    value = row.get("status") or row.get("interpreted_status") or row.get("call_status")
    assert isinstance(value, str), f"Missing interpreted status column in {row}"
    return value.lower()


def test_vendored_strchive_catalog_has_expansionhunter_shape() -> None:
    catalog = json.loads(_read_text(EXPECTED_CATALOG_PATH))

    assert isinstance(catalog, list)
    assert len(catalog) >= 50

    required_keys = {
        "LocusId",
        "VariantType",
        "ReferenceRegion",
        "LocusStructure",
        "DisplayRU",
        "Gene",
        "Disease",
        "NormalMax",
        "PathologicMin",
    }
    for entry in catalog:
        assert required_keys <= set(entry), entry
        variant_types = entry["VariantType"]
        if isinstance(variant_types, str):
            variant_types = [variant_types]
        assert set(variant_types) == {"Repeat"}
        reference_regions = entry["ReferenceRegion"]
        if isinstance(reference_regions, str):
            reference_regions = [reference_regions]
        assert reference_regions
        for region in reference_regions:
            assert re.match(r"^chr(?:[0-9]{1,2}|X|Y|M):[0-9]+-[0-9]+$", region)
        locus_structures = entry["LocusStructure"]
        if isinstance(locus_structures, str):
            locus_structures = [locus_structures]
        assert locus_structures
        assert all(structure.startswith("(") for structure in locus_structures)
        assert entry["DisplayRU"]

    assert any(entry["LocusId"] == "HD_HTT" for entry in catalog)
    assert any(entry["LocusId"] == "FXS_FMR1" for entry in catalog)


@pytest.mark.parametrize(
    "config_path",
    [
        REPO_ROOT / "config" / "supporting_files" / "hg38_supporting_files.yaml",
        REPO_ROOT / "config" / "supporting_files" / "hg38_broad_supporting_files.yaml",
    ],
)
def test_supporting_files_reference_vendored_expansionhunter_catalog(
    config_path: Path,
) -> None:
    text = _read_text(config_path)
    config = _load_yaml(config_path)
    files = config["supporting_files"]["files"]

    assert "strchive" in files
    assert files["strchive"]["disease_loci_hg38_stranger_json"]["name"] == (
        f"resources/strchive/{CATALOG_NAME}"
    )
    assert "https://" not in text[text.index("strchive:") : text.index("strchive:") + 300]


def test_b37_supporting_files_do_not_advertise_hg38_catalog() -> None:
    config = _load_yaml(REPO_ROOT / "config" / "supporting_files" / "b37_supporting_files.yaml")

    assert "strchive" not in config["supporting_files"]["files"]


@pytest.mark.parametrize(
    "rule_config_path",
    [
        REPO_ROOT / "config" / "day_profiles" / "local" / "templates" / "rule_config.yaml",
        REPO_ROOT / "config" / "day_profiles" / "slurm" / "templates" / "rule_config.yaml",
    ],
)
def test_rule_config_declares_expansionhunter_resources(rule_config_path: Path) -> None:
    config = _load_yaml(rule_config_path)

    assert config["expansionhunter"]["env_yaml"] == "../envs/expansionhunter_v0.1.yaml"
    assert config["expansionhunter"]["version"] == "5.0.0"
    assert config["expansionhunter"]["threads"] == 16
    assert config["expansionhunter"]["variant_catalog"] == f"resources/strchive/{CATALOG_NAME}"
    assert config["expansionhunter"]["analysis_mode"] == "seeking"


def test_snakefile_includes_expansionhunter_rule() -> None:
    snakefile = _read_text(REPO_ROOT / "workflow" / "Snakefile")

    assert 'include: "rules/expansionhunter.smk"' in snakefile


def test_expansionhunter_rule_declares_required_outputs_and_command_args() -> None:
    rule_text = _read_text(EXPANSIONHUNTER_RULE)

    for expected in (
        "rule expansionhunter_call:",
        "rule expansionhunter_json_to_tsv:",
        "rule produce_expansion_hunter:",
        "rule produce_expansionhunter:",
        "rule produce_expansionhunter_multiqc:",
        "rule expansionhunter_multiqc:",
        "ExpansionHunter",
        "--reads",
        "--reference",
        "--variant-catalog",
        "--output-prefix",
        "--threads",
        "--analysis-mode",
        "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.json",
        "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.vcf",
        "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.bam",
        "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh_realigned.bam",
        "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.tsv",
        "other_reports/expansionhunter_mqc.tsv",
        "unset LD_PRELOAD",
    ):
        assert expected in rule_text

    assert (
        "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram"
        in rule_text
    )
    assert (
        "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai"
        in rule_text
    )
    assert "config[\"supporting_files\"][\"files\"][\"huref\"][\"fasta\"]" in rule_text
    assert "variant_catalog" in rule_text
    assert "--min-locus-coverage" not in rule_text


def test_expansionhunter_rule_routes_supported_short_read_platforms() -> None:
    rule_text = _read_text(EXPANSIONHUNTER_RULE)

    for aligner in ("sent", "sentcg", "ug"):
        assert re.search(rf"['\"]{aligner}['\"]", rule_text), aligner

    assert "EXPANSIONHUNTER_DEDUP_ALIGNERS" in rule_text
    assert "wildcards.alnr in EXPANSIONHUNTER_DEDUP_ALIGNERS" in rule_text
    assert "wildcards.ddup == \"na\"" in rule_text
    assert "wildcards.alnr == \"ug\"" in rule_text
    assert "wildcards.ddup != \"na\"" in rule_text
    assert "_expansionhunter_sample_supports_aligner" in rule_text
    assert "lambda wildcards: _expansionhunter_target_paths(\"tsv\")" in rule_text
    assert "SEQ_VENDOR" in rule_text
    assert "SEQ_PLATFORM" in rule_text
    assert "ULTIMA_CRAM_ALIGNER" in rule_text
    assert not re.search(r"['\"]ont['\"]", rule_text)
    assert not re.search(r"['\"]pb['\"]", rule_text)


def test_expansionhunter_rule_defaults_invalid_sample_sex_to_male_and_logs() -> None:
    rule_text = _read_text(EXPANSIONHUNTER_RULE)
    common_text = _read_text(REPO_ROOT / "workflow" / "rules" / "common.smk")
    sex_section = rule_text.lower()

    assert "--sex" in rule_text
    assert "sample_sex" in sex_section or "sex" in sex_section
    assert "sample_sex_for_required_tool(wildcards, \"ExpansionHunter\")" in rule_text
    assert "sample_sex_assumption_log(" in rule_text
    assert "printf '%s' {params.sex_assumption_log:q} >> {log:q}" in rule_text
    assert "requires biological sex for sample" not in rule_text
    assert "VALID_REQUIRED_SAMPLE_SEXES" in common_text
    assert 'return "male"' in common_text
    assert "default=\"female\"" not in sex_section
    assert "get(\"sex\", \"female\")" not in sex_section
    assert "get('sex', 'female')" not in sex_section


def test_parser_emits_interpreted_statuses_from_thresholds(tmp_path: Path) -> None:
    module = _load_module(PARSER_PATH, "expansionhunter_parser_under_test")
    catalog_path = tmp_path / "catalog.json"
    json_path = tmp_path / "eh.json"

    catalog_path.write_text(
        json.dumps(
            [
                {
                    "LocusId": "NORMAL",
                    "VariantId": "NORMAL",
                    "VariantType": "Repeat",
                    "ReferenceRegion": "chr1:100-130",
                    "LocusStructure": "(CAG)*",
                    "DisplayRU": "CAG",
                    "Gene": "GENE1",
                    "Disease": "Disease one",
                    "NormalMax": 30,
                    "PathologicMin": 40,
                },
                {
                    "LocusId": "INTERMEDIATE",
                    "VariantId": "INTERMEDIATE",
                    "VariantType": "Repeat",
                    "ReferenceRegion": "chr2:200-230",
                    "LocusStructure": "(GAA)*",
                    "DisplayRU": "GAA",
                    "Gene": "GENE2",
                    "Disease": "Disease two",
                    "NormalMax": 30,
                    "PathologicMin": 40,
                },
                {
                    "LocusId": "PATHOGENIC",
                    "VariantId": "PATHOGENIC",
                    "VariantType": "Repeat",
                    "ReferenceRegion": "chr3:300-330",
                    "LocusStructure": "(CGG)*",
                    "DisplayRU": "CGG",
                    "Gene": "GENE3",
                    "Disease": "Disease three",
                    "NormalMax": 30,
                    "PathologicMin": 40,
                },
            ]
        ),
        encoding="utf-8",
    )
    json_path.write_text(
        json.dumps(
            {
                "SampleParameters": {"SampleId": "HG002", "Sex": "Female"},
                "LocusResults": {
                    "NORMAL": {
                        "Variants": {
                            "NORMAL": {
                                "Genotype": "22/29",
                                "GenotypeConfidenceInterval": "22-22/28-30",
                                "RepeatUnit": "CAG",
                                "ReferenceRegion": "chr1:100-130",
                            }
                        },
                        "Coverage": 41.5,
                    },
                    "INTERMEDIATE": {
                        "Variants": {
                            "INTERMEDIATE": {
                                "Genotype": "31/39",
                                "GenotypeConfidenceInterval": "31-32/38-39",
                                "RepeatUnit": "GAA",
                                "ReferenceRegion": "chr2:200-230",
                            }
                        },
                        "Coverage": 40.0,
                    },
                    "PATHOGENIC": {
                        "Variants": {
                            "PATHOGENIC": {
                                "Genotype": "42/45",
                                "GenotypeConfidenceInterval": "42-43/44-46",
                                "RepeatUnit": "CGG",
                                "ReferenceRegion": "chr3:300-330",
                            }
                        },
                        "Coverage": 39.8,
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    rows = _call_parser(module, json_path, catalog_path)

    assert len(rows) == 3
    assert _status(_row_by_locus(rows, "NORMAL")) == "normal"
    assert _status(_row_by_locus(rows, "INTERMEDIATE")) == "intermediate_or_uncertain"
    assert _status(_row_by_locus(rows, "PATHOGENIC")) == "pathogenic_range"
    for row in rows:
        assert row.get("sample") == "HG002"
        assert row.get("aligner") == "sent"
        assert row.get("deduper") == "dmd"
        assert row.get("gene")
        assert row.get("disease")
        assert row.get("catalog_reference_region")
        assert row.get("display_repeat_unit")
        assert row.get("genotype")
        assert row.get("genotype_confidence_interval")
        assert row.get("coverage") is not None
        assert row.get("normal_max") == "30"
        assert row.get("pathologic_min") == "40"


def test_parser_rejects_malformed_json(tmp_path: Path) -> None:
    module = _load_module(PARSER_PATH, "expansionhunter_parser_malformed_under_test")
    catalog_path = tmp_path / "catalog.json"
    json_path = tmp_path / "broken.json"

    catalog_path.write_text("[]", encoding="utf-8")
    json_path.write_text('{"LocusResults": ', encoding="utf-8")

    with pytest.raises((json.JSONDecodeError, ValueError, SystemExit)):
        _call_parser(module, json_path, catalog_path)


def test_multiqc_config_exposes_expansionhunter_custom_content() -> None:
    config = _load_yaml(REPO_ROOT / "config" / "external_tools" / "multiqc_config.yaml")

    assert "expansionhunter" in config["module_order"]
    assert "expansionhunter" in config["custom_data"]
    assert "expansionhunter" in config["sp"]

    custom = config["custom_data"]["expansionhunter"]
    assert custom["id"] == "expansionhunter"
    assert custom["section_name"] == "ExpansionHunter STR Report"
    assert "STR" in custom["description"]
    assert custom["file_format"] == "tsv"
    assert custom["plot_type"] == "table"
    assert custom["pconfig"]["id"] == "expansionhunter"

    assert config["sp"]["expansionhunter"]["fn"] == "other_reports/expansionhunter_mqc.tsv"
