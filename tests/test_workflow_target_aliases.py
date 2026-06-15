from __future__ import annotations

import csv
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = REPO_ROOT / "config/workflow_target_aliases.tsv"


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _registry() -> list[dict[str, str]]:
    with REGISTRY_PATH.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def _rows(kind: str, status: str | None = None) -> list[dict[str, str]]:
    rows = [row for row in _registry() if row["kind"] == kind]
    if status is not None:
        rows = [row for row in rows if row["status"] == status]
    return rows


def test_registry_has_expected_schema_and_canonical_codes() -> None:
    rows = _registry()
    assert rows
    assert set(rows[0]) == {"target", "kind", "code", "status", "delegates_to"}

    assert {row["code"] for row in _rows("deduper", "current")} == {
        "dmd",
        "smd",
        "na",
        "all",
    }
    assert not [
        row
        for row in _rows("deduper", "current")
        if row["code"] == "dppl" or row["target"].startswith("produce_dppl")
    ]
    assert any(
        row["target"] == "dedup_doppelmark"
        and row["code"] == "dmd"
        and row["status"] == "deprecated"
        for row in rows
    )


def test_current_selector_targets_exist_and_have_delegates() -> None:
    selector_rules = _read("workflow/rules/workflow_target_aliases.smk")
    snakefile = _read("workflow/Snakefile")

    assert 'include: "rules/workflow_target_aliases.smk"' in snakefile
    for row in _registry():
        if row["status"] != "current":
            continue
        assert f"rule {row['target']}:" in selector_rules
        rule_line = next(
            line for line in selector_rules.splitlines() if line.startswith(f"rule {row['target']}:")
        )
        assert "# TARGET:" in rule_line
        if row["code"] != "all":
            assert row["delegates_to"], row


def test_all_targets_expand_complete_registered_sets() -> None:
    selector_rules = _read("workflow/rules/workflow_target_aliases.smk")
    bin_day_run = _read("bin/day_run")
    common = _read("workflow/rules/common.smk")

    for target in (
        "produce_all_align",
        "produce_all_dedup_cram",
        "produce_all_snv_vcf",
        "produce_all_sv_vcf",
    ):
        assert f"rule {target}:" in selector_rules

    assert 'if [[ "$_rcode" == "all" ]]' in bin_day_run
    assert '$_astatus" == "current"' in bin_day_run
    assert "if row[\"code\"] == \"all\":" in common
    assert "codes.update(_current_alias_codes(kind))" in common
    assert "sentpgs" not in {row["code"] for row in _rows("snv_caller", "current")}


def test_selector_targets_handle_aggregate_delegates_with_explicit_inputs() -> None:
    selector_rules = _read("workflow/rules/workflow_target_aliases.smk")

    assert 'if delegate == "dedup_none":' in selector_rules
    assert "def _workflow_na_dedup_inputs" in selector_rules
    assert "valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)" in selector_rules
    assert "{sample}.{alnr}.na.cram.crai" in selector_rules
    assert "{sample}.{alnr}.na.bam.bai" in selector_rules
    assert 'if delegate == "produce_sentmm2_align_sort":' in selector_rules
    assert 'if delegate == "produce_sentmm2ont_align_sort":' in selector_rules


def test_auto_config_injection_covers_all_selector_dimensions() -> None:
    bin_day_run = _read("bin/day_run")
    common = _read("workflow/rules/common.smk")

    for env_var in (
        "_DY_AUTO_ALIGNERS",
        "_DY_AUTO_DEDUPERS",
        "_DY_AUTO_SNV_CALLERS",
        "_DY_AUTO_SV_CALLERS",
    ):
        assert env_var in bin_day_run
        assert env_var in common

    assert "_dy_add_registry_target_codes" in bin_day_run
    assert "sv_callers=*" in bin_day_run
    assert "def _target_alias_codes_from_argv" in common
    assert 'DDUP_LEGACY_MAP = {"dppl": "dmd", "dppl_sent": "smd"}' in common
    assert 'DDUP_VALID_CODES = set(CANONICAL_DEDUPER_CODES) | {"spmd"}' in common
    assert "Legacy dppl is accepted and normalized to dmd." in common


def test_experimental_sharded_pangenome_target_autoconfigs_without_current_selector() -> None:
    selector_rules = _read("workflow/rules/workflow_target_aliases.smk")
    rows = _registry()

    assert {
        (row["kind"], row["code"], row["status"])
        for row in rows
        if row["target"] == "produce_pangenome_ug_sharded_vcf"
    } == {
        ("aligner", "pangenome_ug", "experimental"),
        ("snv_caller", "sentpgs", "experimental"),
    }
    assert "rule produce_pangenome_ug_sharded_vcf:" not in selector_rules


def test_multiqc_canonical_targets_and_deprecated_aliases() -> None:
    multiqc = _read("workflow/rules/multiqc_final_wgs.smk")

    for target in (
        "produce_multiqc_input_data",
        "produce_multiqc_cram",
        "produce_multiqc_snv",
        "produce_multiqc_sv",
        "produce_multiqc_sample_qc",
        "produce_multiqc_variant_annotation",
        "produce_multiqc_all",
    ):
        assert f"rule {target}:" in multiqc

    for old_target in (
        "produce_multiqc_seq_data",
        "produce_multiqc_alignment",
        "produce_multiqc_variants",
        "produce_multiqc_final",
        "produce_multiqc_final_wgs",
    ):
        marker = f"rule {old_target}:  # DEPRECATED TARGET:"
        assert marker in multiqc


def test_kitchen_sink_target_delegates_current_broad_evidence_targets() -> None:
    selector_rules = _read("workflow/rules/workflow_target_aliases.smk")
    current_all_targets = {
        row["target"]
        for row in _registry()
        if row["status"] == "current" and row["code"] == "all"
    }

    assert "produce_kitchen_sink," in selector_rules
    assert "rule produce_kitchen_sink:" in selector_rules
    for target in current_all_targets:
        assert f'"{target}"' in selector_rules
        assert f'_workflow_target_alias_marker("{target}")' in selector_rules

    for expected in (
        "produce_alignstats",
        "produce_snv_concordances",
        "produce_relatedness",
        "produce_vep",
        "produce_htd_calls",
        "produce_expansionhunter",
        "longtr_all",
        "longtr_diseaser",
        "produce_metagenomics",
        "produce_global_contam_check",
        "produce_multiqc_all",
        "produce_dayoa_evidence_manifest",
        "DAY_final_multiqc.html",
        "dayoa_evidence_manifest.json",
    ):
        assert f'"{expected}"' in selector_rules or expected in selector_rules

    for retired in (
        "produce_verifybamid",
        "produce_verifybamid2",
        "parascopy",
        "genetocn",
        "gauchian",
        "smaca",
        "smn12",
        "stargazer",
        "snpeff",
        "qualimap",
    ):
        kitchen_sink_block = selector_rules[
            selector_rules.index("KITCHEN_SINK_TARGETS") : selector_rules.index(
                "rule produce_sent_align:"
            )
        ]
        assert retired not in kitchen_sink_block
