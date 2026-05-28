from __future__ import annotations

import importlib.util
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def _load_converter_module():
    path = REPO_ROOT / "workflow/scripts/convert_expansionhunter_catalog_to_longtr_bed.py"
    spec = importlib.util.spec_from_file_location("convert_expansionhunter_catalog_to_longtr_bed", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_longtr_rule_and_env_are_active() -> None:
    snakefile = _read("workflow/Snakefile")
    rule = _read("workflow/rules/longtr.smk")
    env = _yaml("workflow/envs/longtr_v0.1.yaml")

    assert 'include: "rules/longtr.smk"' in snakefile
    assert "rule longtr:" in rule
    assert "rule longtr_all:" in rule
    assert "rule longtr_diseaser:" in rule
    assert "--bams {input.cram:q}" in rule
    assert "--regions" in rule
    assert "--tr-vcf" in rule
    assert "--bam-samps {params.sample_name:q}" in rule
    assert "LONGTR_ALLOWED_ALIGNERS = {\"ont\", \"sentmm2ont\"}" in rule
    assert "LongTR requires explicit config['longtr']['catalogs']." in rule
    assert "longtr=1.2" in env["dependencies"]


def test_longtr_profile_catalogs_are_explicit() -> None:
    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        cfg = _yaml(path)["longtr"]
        assert cfg["env_yaml"] == "../envs/longtr_v0.1.yaml"
        assert cfg["command"] == "LongTR"
        assert cfg["aligners"] == ["ont", "sentmm2ont"]
        assert cfg["deduper"] == "na"
        assert cfg["catalogs"]["all"]["name"] == "trexplorer_catalog"
        assert cfg["catalogs"]["all"]["regions_bed"].endswith(
            "longtr/trexplorer_catalog/"
            "TRExplorer.repeat_catalog_v2.hg38.1_to_1000bp_motifs.LongTR.bed.gz"
        )
        assert cfg["catalogs"]["diseaser"]["name"] == "disease_repeat_catalog"
        assert cfg["catalogs"]["diseaser"]["regions_bed"].endswith(
            "longtr/disease_repeat_catalog/"
            "dayoa_STRchive-disease-loci.hg38.longtr.bed.gz"
        )


def test_disease_repeat_catalog_converter_contract() -> None:
    module = _load_converter_module()
    catalog = module._read_catalog(
        REPO_ROOT / "resources/strchive/STRchive-disease-loci.hg38.stranger.json"
    )
    rows, skipped = module.convert(catalog)

    assert len(rows) == 94
    assert skipped == [
        "DBQD2_XYLT1\tnon_positive_interval_after_1based_conversion\tchr16:17470907-17470907"
    ]
    assert rows[0] == "chr1\t1435799\t1435818\tGGCGCGGAGC\tHMNR7_VWA1"
    assert "chr1\t57367044\t57367078\tAAAAT\tSCA37_DAB1_AAAAT" in rows
    assert "chr1\t57367079\t57367121\tGAAAT\tSCA37_DAB1" in rows
