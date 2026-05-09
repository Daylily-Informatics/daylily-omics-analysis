from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def test_htd_callers_default_empty_in_profiles() -> None:
    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        assert _yaml(path)["htd_callers"] == []


def test_common_declares_supported_htd_callers_and_validation() -> None:
    common = _read("workflow/rules/common.smk")

    for caller in ("gauchian", "cyrius", "smn12", "parascopy", "smaca", "genetocn"):
        assert f'"{caller}"' in common
    assert "SUPPORTED_HTD_CALLERS" in common
    assert "def htd_callers_selected" in common
    assert "Unsupported htd_callers value" in common
    assert "produce_htd_calls requires a non-empty" in common


def test_cyrius_included_and_stargazer_intentionally_excluded() -> None:
    snakefile = _read("workflow/Snakefile")
    active_includes = [
        line.strip()
        for line in snakefile.splitlines()
        if line.strip().startswith("include:")
    ]

    assert 'include: "rules/cyp2d6_cyrius.smk"' in snakefile
    assert 'include: "rules/htd_calls.smk"' in snakefile
    assert 'include: "rules/stargazer.smk"' not in active_includes
    assert "Stargazer is intentionally excluded from htd_callers" in snakefile
    assert '# include: "rules/stargazer.smk"' in snakefile


def test_cyrius_rule_uses_documented_interface_and_outputs() -> None:
    cyrius = _read("workflow/rules/cyp2d6_cyrius.smk")

    for expected in (
        "rule cyrius:",
        "rule produce_cyrius:",
        "htd/cyrius",
        ".cyrius.tsv",
        ".cyrius.json",
        ".cyrius.done",
        "--manifest {output.manifest}",
        "--genome {params.genome}",
        "--reference {params.huref}",
        "--prefix {params.prefix}",
        "--outDir {params.out_dir}",
        "--threads {threads}",
        "realpath {input.cram}",
        "resources/cyrius/v0.0.0.6-jem/data",
        "star_table.txt",
        "runtime_dir",
        '"$CONDA_PREFIX/bin/python" {params.runtime_dir}/star_caller.py',
        '"../envs/cyrius_v0.1.yaml"',
    ):
        assert expected in cyrius
    assert "rule produce_cyp2d6" not in cyrius
    assert "htd/cyp2d6" not in cyrius
    assert '"logs/cyrius.done"' in cyrius


def test_cyrius_vendored_resources_present() -> None:
    data_dir = REPO_ROOT / "resources/cyrius/v0.0.0.6-jem/data"

    for name in (
        "star_table.txt",
        "CYP2D6_region_38.bed",
        "CYP2D6_SNP_38.txt",
        "CYP2D6_target_variant_38.txt",
        "CYP2D6_target_variant_homology_region_38.txt",
        "CYP2D6_haplotype_38.txt",
        "CYP2D6_gmm.txt",
    ):
        assert (data_dir / name).is_file()
        assert (data_dir / name).stat().st_size > 0


def test_htd_selector_maps_supported_callers_to_outputs() -> None:
    htd = _read("workflow/rules/htd_calls.smk")

    for expected in (
        "def htd_call_outputs",
        "required_htd_call_outputs",
        "rule htd_calls_mqc:",
        "rule produce_htd_calls:",
        "other_reports/htd_calls_mqc.tsv",
        "workflow/scripts/htd_calls_mqc.py",
        '"logs/htd_calls.done"',
        "gauchian.done",
        "cyrius.tsv",
        "cyrius.json",
        "smn12.summary.json",
        "parascopy.done",
        "smaca.summary.tsv",
        "genetocn.done",
    ):
        assert expected in htd


def test_htd_mqc_script_schema_and_cyrius_fields() -> None:
    script = _read("workflow/scripts/htd_calls_mqc.py")

    for expected in (
        "HTD_RE",
        "CYP2D6",
        "Genotype",
        "Filter",
        "json_path",
        "tsv_path",
        "done_path",
        "output_paths",
        "csv.DictWriter",
    ):
        assert expected in script


def test_selector_facing_aggregate_paths_include_deduper() -> None:
    gauchian = _read("workflow/rules/gauchian.smk")
    smn12 = _read("workflow/rules/smn_copynumbercaller.smk")
    parascopy = _read("workflow/rules/parascopy.smk")
    smaca = _read("workflow/rules/smaca.smk")
    genetocn = _read("workflow/rules/genetocn.smk")

    for text in (gauchian, smn12, parascopy, smaca, genetocn):
        assert "QC_CRAM_ALIGNERS" in text
    assert "def genetocn_cram" in genetocn
    assert "def genetocn_inputs" not in genetocn
    assert "cram=genetocn_cram" in genetocn
    assert "{sample}/align/{alnr}/{ddup}/htd/parascopy/{sample}.{alnr}.{ddup}.parascopy.done" in parascopy
    assert "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done" in smaca


def test_final_multiqc_and_multiqc_config_include_htd_when_selected() -> None:
    final = _read("workflow/rules/multiqc_final_wgs.smk")
    multiqc = _yaml("config/external_tools/multiqc_config.yaml")

    assert "if HTD_CALLERS:" in final
    assert "htd_calls_mqc.tsv" in final
    assert "htd_calls" in multiqc["custom_data"]
    assert multiqc["sp"]["htd_calls"]["fn"] == "other_reports/htd_calls_mqc.tsv"
