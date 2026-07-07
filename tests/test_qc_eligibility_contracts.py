from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_common_declares_metadata_only_control_and_qc_helpers() -> None:
    common = _read("workflow/rules/common.smk")

    for expected in (
        "POSITIVE_CONTROL_SAMPLE_TYPE_TOKENS",
        "NEGATIVE_CONTROL_SAMPLE_TYPE_TOKENS",
        "def is_positive_control_sample(sample):",
        "def is_negative_control_or_ntc_sample(sample):",
        "def is_control_sample(sample):",
        "def qc_eligible_sample_ids(sample_ids=None):",
        "def require_qc_eligible_sample(wildcards_or_sample, tool_name):",
        "info.get(\"is_positive_control\")",
        "info.get(\"is_negative_control\")",
        "info.get(\"sample_type\"",
        "QC_ELIGIBLE_SAMPLES = qc_eligible_sample_ids(SSAMPS)",
    ):
        assert expected in common

    assert "def qc_variant_dedupers():" in common
    assert 'if ddup != "na"' in common


def test_peddy_targets_exclude_ntc_controls_and_no_dedup_leaks() -> None:
    peddy = _read("workflow/rules/peddy.smk")

    assert 'require_qc_eligible_sample(wildcards, "Peddy")' in peddy
    assert "for sample in QC_ELIGIBLE_SAMPLES" in peddy
    assert "valid_snv_alnr_ddup_tuples(" in peddy
    assert "for ddup in DDUP" not in peddy


def test_site_mix_targets_exclude_ntc_controls() -> None:
    site_mix = _read("workflow/rules/site_mix_contam.smk")
    target = site_mix[site_mix.index("rule produce_site_mix_contam_estimate:") :]

    assert "def _site_mix_qc_samples():" in site_mix
    assert "return qc_eligible_sample_ids(SSAMPS)" in site_mix
    assert 'require_qc_eligible_sample(\n            wildcards, "site_mix_contam"' in site_mix
    assert "sample_ids=_site_mix_qc_samples()" in site_mix
    assert "expand_qc_contamination(" in target
    assert '"logs/site_mix_contam_estimate.done"' in target
    assert "touch {output:q}" in target


def test_relatedness_uses_control_filtered_samples_and_declared_outputs() -> None:
    relatedness = _read("workflow/rules/relatedness_batch.smk")

    for expected in (
        "RELATEDNESS_SAMPLES = qc_eligible_sample_ids(SSAMPS)",
        "for sample in RELATEDNESS_SAMPLES:",
        "sample=RELATEDNESS_SAMPLES",
        'require_qc_eligible_sample(\n            wildcards, "Somalier relatedness"',
        "sample_count=lambda wildcards: len(RELATEDNESS_SAMPLES)",
        "cohort.samples.tsv",
        "cohort.pairs.tsv",
        "cohort.groups.tsv",
        "cohort.html",
        "somalier relate {input:q} -o {params.prefix:q}",
        "declared cohort output",
    ):
        assert expected in relatedness


def test_expansionhunter_filters_controls_and_requires_manifest_sex() -> None:
    expansionhunter = _read("workflow/rules/expansionhunter.smk")
    multiqc = _read("workflow/rules/multiqc_final_wgs.smk")

    for expected in (
        "def _expansionhunter_target_samples():",
        "return qc_eligible_sample_ids(SSAMPS)",
        "for sample in _expansionhunter_target_samples():",
        "def _expansionhunter_should_derive_sample_sex(sample):",
        "return False",
        "_expansionhunter_target_paths(\"tsv\", require=True)",
        "_expansionhunter_require_non_control_sample_sex(sample)",
        "_expansionhunter_require_non_control_sample_sex(wildcards.sample)",
        'require_qc_eligible_sample(wildcards, "ExpansionHunter")',
        "VALID_REQUIRED_SAMPLE_SEXES",
        "BIOLOGICAL_SEX=male/female",
        "not derived or guessed",
        "Missing, empty, na, and unk values",
        "before DAG ",
        "construction for non-control sample",
        "is_negative_control=true or sample_type=NTC",
    ):
        assert expected in expansionhunter

    assert "expansionhunter_report_targets_available()" in multiqc


def test_snpeff_produce_rule_is_not_help_visible_target() -> None:
    snpeff = _read("workflow/rules/snpeff.smk")

    produce_line = next(
        line for line in snpeff.splitlines() if line.startswith("rule produce_snpeff:")
    )
    assert "# TARGET" not in produce_line
    assert "DISABLED" in produce_line
