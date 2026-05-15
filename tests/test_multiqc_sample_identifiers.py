from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def assert_valid_multiqc_sample_id(
    value: str,
    *,
    requires_deduper: bool = False,
    requires_caller: bool = False,
    chromosome_scattered: bool = False,
) -> None:
    assert value not in {"R1", "R2"}
    for bad in (".metrics", "_FR", "-sent-dmd-cram"):
        assert bad not in value
    parts = value.split(".")
    if requires_deduper:
        assert len(parts) >= 3
    if requires_caller:
        assert len(parts) >= 4
    if chromosome_scattered:
        assert parts[-1].startswith("chr")


@pytest.mark.parametrize(
    "bad_id",
    [
        "R1",
        "R2",
        "HG002.metrics",
        "HG002_FR",
        "R0-HG002-sent-dmd-cram",
    ],
)
def test_sample_identifier_validator_rejects_historical_bad_patterns(bad_id: str) -> None:
    with pytest.raises(AssertionError):
        assert_valid_multiqc_sample_id(bad_id, requires_deduper=True)


def test_custom_output_inventory_uses_stage_aware_sample_first_column(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/multiqc_custom_output_inventory.py",
        "multiqc_custom_output_inventory_under_test",
    )
    path = (
        tmp_path
        / "results/day/hg38/HG001/align/sent/dmd/alignqc/samtmetrics/"
        / "HG001.sent.dmd.complete"
    )
    path.parent.mkdir(parents=True)
    path.write_text("done\n", encoding="utf-8")

    row = module._infer_record("alignment_qc", str(path))

    assert row["Sample"] == "HG001.sent.dmd"
    assert row["base_sample"] == "HG001"
    assert row["aligner"] == "sent"
    assert row["deduper"] == "dmd"
    assert_valid_multiqc_sample_id(str(row["Sample"]), requires_deduper=True)


def test_sequence_and_coverage_custom_tsv_contracts_are_sample_first() -> None:
    seqfu = _read("workflow/rules/seqfu.smk")
    coverage = _read("workflow/rules/calc_coverage_eveness.smk")
    multiqc_final = _read("workflow/rules/multiqc_final_wgs.smk")
    multiqc_cov_aln = _read("workflow/rules/multiqc_cov_aln.smk")

    assert 'printf "Sample\\\\tbase_sample\\\\tread\\\\tsource_path\\\\n" > {output.mqc};' in seqfu
    assert 'printf "%s.R1\\\\t%s\\\\tR1\\\\t%s\\\\n"' in seqfu
    assert 'printf "%s.R2\\\\t%s\\\\tR2\\\\t%s\\\\n"' in seqfu
    assert (
        'echo "Sample\\tbase_sample\\tCHRM\\tmeanRawCov'
        in coverage
    )
    assert '"{params.stage_sample}.{params.chrm}$i"' in coverage
    assert "norm_cov_evenness_combo_mqc.tsv" in coverage
    assert "norm_cov_evenness_combo_mqc.tsv" in multiqc_final
    assert "norm_cov_evenness_combo_mqc.tsv" in multiqc_cov_aln
    assert "normcovevenness_combo_mqc.tsv" not in coverage
    assert "normcovevenness_combo_mqc.tsv" not in multiqc_final


def test_variant_and_concordance_custom_tsvs_include_full_stage_identity() -> None:
    bcftools = _read("workflow/rules/bcftools_vcfstat.smk")
    rtg_vcfstats = _read("workflow/rules/rtg_vcfstats.smk")
    snpeff = _read("workflow/rules/snpeff.smk")
    vep = _read("workflow/rules/vep.smk")
    peddy = _read("workflow/rules/peddy.smk")
    concordance = _read("workflow/rules/rtg_vcfeval.smk")
    concordance_parser = _read("workflow/scripts/parse-vcfeval-summary.py")

    for text in (bcftools, rtg_vcfstats, snpeff, vep, peddy):
        assert '"Sample",' in text
        assert '"base_sample",' in text
        assert '"sample_id": sample' not in text
        assert '"sample_id": sample_id' not in text
        assert "day_stage_sample_id(sample, aligner, deduper, caller)" in text

    assert "{wildcards.ddup}" in concordance
    assert "Sample" in concordance_parser
    assert "VariantClass" in concordance_parser
    assert "InputSample" in concordance_parser
    assert "Deduper" in concordance_parser
    assert "f\"{stage_sample}.{variant_class}\"" in concordance_parser
    assert "mqc_id" not in concordance_parser
    aggregate_rule = concordance[concordance.index("rule produce_snv_concordances:") :]
    assert "perl -pi" not in aggregate_rule
    assert "\n    conda:" not in aggregate_rule


def test_native_multiqc_collision_modules_are_excluded_and_cleaned() -> None:
    multiqc = _read("config/external_tools/multiqc_config.yaml")
    picard = _read("workflow/rules/picard.smk")

    assert "\n  - peddy\n" in multiqc[multiqc.index("exclude_modules:") :]
    assert "\n  - somalier\n" in multiqc[multiqc.index("exclude_modules:") :]
    assert "\n  - peddy\n" not in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    assert "\n  - somalier\n" not in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    assert 'peddy/background_pca:' not in multiqc
    assert r"^(.*)-([A-Za-z0-9_]+)-(dppl|dmd|smd|spmd|na)-cram$" in multiqc
    assert r"\.metrics$" in multiqc
    assert "_FR$" in multiqc
    assert ".alignment_summary_metrics.txt" in multiqc
    assert ".insert_size_metrics.txt" in multiqc
    assert "O={params.prefix:q}" in picard
    assert "O=$pic_d" not in picard
