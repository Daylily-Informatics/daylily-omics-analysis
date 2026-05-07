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


def test_snakefile_includes_repaired_qc_rules() -> None:
    snakefile = _read("workflow/Snakefile")

    assert 'include: "rules/fastp.smk"' not in snakefile
    for include in (
        'include: "rules/fastv.smk"',
        'include: "rules/seqfu.smk"',
        'include: "rules/relatedness_batch.smk"',
    ):
        assert include in snakefile


def test_multiqc_runtime_gate_config_defaults() -> None:
    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        config = _yaml(path)
        gate = config["multiqc_qc"]
        assert gate["enable_long_running"] is False
        assert gate["enable_tools"] == []
        assert gate["disable_tools"] == []
        assert gate["include_no_dedup_alignment_qc"] is True
        assert gate["runtime_gate_minutes"] == 45
        assert config["no_dedup"]["env_yaml"] == "../envs/samtools_v0.1.yaml"
        assert "relatedness" in config
        assert config["relatedness"]["somalier_sites_vcf"].endswith(
            "merged.500perchr.nosamp.sort.vcf.gz"
        )


def test_common_declares_runtime_gate_helpers_and_cram_qc_scope() -> None:
    common = _read("workflow/rules/common.smk")

    assert "MULTIQC_QC_LONG_RUNNING_TOOLS" in common
    for tool in ("fastv", "kat", "vep", "snpeff"):
        assert f'"{tool}"' in common
    assert "def qc_tool_enabled" in common
    assert "def qc_alignment_dedupers" in common
    assert "QC_CRAM_ALIGNERS=sorted(set(ALL_ALIGNERS)-set(BAM_ALIGNERS))" in common


def test_staged_multiqc_targets_and_dependencies_exist() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")

    for rule_name in (
        "rule produce_multiqc_seq_data:",
        "rule produce_multiqc_alignment:",
        "rule produce_multiqc_variants:",
        "rule produce_multiqc_final:",
        "rule produce_multiqc_final_wgs:",
    ):
        assert rule_name in text

    assert 'MDIR + "reports/DAY_final_multiqc.html"' in text
    assert "def _seq_data_component_inputs" in text
    assert "def _alignment_component_inputs" in text
    assert "def _variant_component_inputs" in text
    assert 'qc_tool_enabled("fastp")' not in text
    assert "seqqc/fastp" not in text
    assert "qc_tool_enabled(\"fastv\", long_running=True)" in text
    assert "qc_tool_enabled(\"kat\", long_running=True)" in text
    assert "qc_tool_enabled(\"vep\", long_running=True)" in text
    assert "qc_tool_enabled(\"snpeff\", long_running=True)" in text
    assert "QC_CRAM_ALIGNERS" in text
    assert "qc_alignment_dedupers()" in text
    for expected in (
        "sequence_qc_outputs_mqc.tsv",
        "alignment_qc_outputs_mqc.tsv",
        "contamination_mqc.tsv",
        "site_mix_contam_mqc.tsv",
        "site_mix_donor_mqc.tsv",
        "relatedness_mqc.tsv",
        "bcftools_variant_stats_mqc.tsv",
        "rtg_vcfstats_mqc.tsv",
        "peddy_sample_qc_mqc.tsv",
        "expansionhunter_mqc.tsv",
        "vep_annotation_mqc.tsv",
        "snpeff_annotation_mqc.tsv",
        "rules_benchmark_data_mqc.tsv",
    ):
        assert expected in text


def test_sequence_qc_repairs_are_strict_and_multiqc_ready() -> None:
    fastp = _read("workflow/rules/fastp.smk")
    fastv = _read("workflow/rules/fastv.smk")
    seqfu = _read("workflow/rules/seqfu.smk")
    multiqc = _read("config/external_tools/multiqc_config.yaml")

    assert "bench=MDIR" not in fastp
    assert ": > {log.a};" in fastp
    assert "{input.fpqr1s}" in fastv
    assert "{input.fpqr2s}" in fastv
    assert "mkdir -p $(dirname {output});" in fastv
    assert "find {params.mdir} -name '*seqfuR1.mqc.tsv'" in seqfu
    assert "parallel" not in seqfu
    assert "other_reports/seqfu_mqc.tsv" in seqfu
    assert "\n  - fastp\n" not in multiqc


def test_fastp_is_not_pulled_by_staged_multiqc_targets() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")

    assert "rule produce_fastp:" not in text
    assert ".fastp.done" not in text
    assert ".fastp.json" not in text
    assert ".fastp.html" not in text


def test_multiqc_custom_output_inventory_rules_exist() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")
    script = _read("workflow/scripts/multiqc_custom_output_inventory.py")

    for expected in (
        "def _sequence_qc_native_inputs",
        "def _alignment_qc_native_inputs",
        "rule sequence_qc_outputs_custom_data:",
        "rule alignment_qc_outputs_custom_data:",
        "workflow/scripts/multiqc_custom_output_inventory.py",
        "sequence_qc_outputs_mqc.tsv",
        "alignment_qc_outputs_mqc.tsv",
    ):
        assert expected in text

    for expected in (
        "csv.DictWriter",
        "sample",
        "stage",
        "tool",
        "source_path",
        "ALIGNQC_RE",
        "SEQQC_RE",
    ):
        assert expected in script


def test_contamination_and_relatedness_aggregates_are_wired() -> None:
    site_mix = _read("workflow/rules/site_mix_contam.smk")
    relatedness = _read("workflow/rules/relatedness_batch.smk")
    report_script = _read("workflow/scripts/relatedness_report.py")
    report_env = _yaml("workflow/envs/report.yaml")

    assert "rule contamination_mqc_gather:" in site_mix
    for expected in (
        "verifybamid2",
        "gatk",
        "site_mix",
        "contamination_mqc.tsv",
        "site_mix_contam_mqc.tsv",
        "site_mix_donor_mqc.tsv",
        "QC_CRAM_ALIGNERS",
        "qc_alignment_dedupers()",
    ):
        assert expected in site_mix

    for expected in (
        "rule relatedness_batch_manifest:",
        "rule relatedness_batch_somalier_extract:",
        "rule relatedness_batch_somalier_relate:",
        "rule relatedness_batch_report:",
        "rule relatedness_batch_gather:",
        "rule produce_relatedness:",
        "relatedness_mqc.tsv",
        "QC_CRAM_ALIGNERS",
        "qc_alignment_dedupers()",
    ):
        assert expected in relatedness

    assert "PAIR_COLUMNS" in report_script
    assert "relationship\": \"no_pairs\"" in report_script
    extract_rule = relatedness[
        relatedness.index("rule relatedness_batch_somalier_extract:") :
        relatedness.index("rule relatedness_batch_somalier_relate:")
    ]
    assert "--genome-build" not in extract_rule
    assert "-o {params.prefix:q}" not in extract_rule
    assert "--out-dir {params.out_dir:q}" in extract_rule
    assert "--sample-prefix" not in extract_rule
    assert "setuptools" in report_env["dependencies"]


def test_no_dedup_uses_samtools_conda_env() -> None:
    rule_text = _read("workflow/rules/no_dedup.smk")
    samtools_env = _read("workflow/envs/samtools_v0.1.yaml")

    assert 'conda:\n        config["no_dedup"]["env_yaml"]' in rule_text
    assert "samtools view" in rule_text
    assert "samtools" in samtools_env


def test_variant_qc_and_annotation_summaries_are_wired() -> None:
    bcftools = _read("workflow/rules/bcftools_vcfstat.smk")
    rtg = _read("workflow/rules/rtg_vcfstats.smk")
    peddy = _read("workflow/rules/peddy.smk")
    vep = _read("workflow/rules/vep.smk")
    snpeff = _read("workflow/rules/snpeff.smk")

    assert "rule bcftools_variant_stats_gather:" in bcftools
    assert "bcftools_variant_stats_mqc.tsv" in bcftools
    assert "rule rtg_vcfstats_gather:" in rtg
    assert "rtg_vcfstats_mqc.tsv" in rtg
    assert "rule peddy_sample_qc_gather:" in peddy
    assert "peddy_sample_qc_mqc.tsv" in peddy
    assert "--input_file {input.vcfgz}" in vep
    assert "--assembly {params.genome_build}" in vep
    assert "--dir_cache {params.vep_cache}" in vep
    assert "--cache_version {params.cache_version}" in vep
    assert "--cache {params.vep_cache}" not in vep
    assert "vep_annotation_mqc.tsv" in vep
    assert "valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)" in vep
    assert "bgzip -c > {output.annovcf}" in snpeff
    assert "snpeff_annotation_mqc.tsv" in snpeff


def test_multiqc_config_custom_content_entries() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")

    for key in (
        "seqfu",
        "sequence_qc_outputs",
        "alignment_qc_outputs",
        "contamination",
        "site_mix_contam",
        "site_mix_donor",
        "relatedness",
        "bcftools_variant_stats",
        "rtg_vcfstats",
        "peddy_sample_qc",
        "vep_annotation",
        "snpeff_annotation",
        "htd_calls",
        "expansionhunter",
    ):
        assert key in config["custom_data"]
        assert key in config["sp"]

    excludes = set(config["exclude_modules"])
    assert "fastp" not in excludes
    assert "vep" not in excludes
    assert "snpeff" not in excludes
    assert "sexdetermine" in excludes


def test_multiqc_runtime_policy_documented() -> None:
    readme = _read("README.md")
    doc = _read("docs/ops/multiqc_qc_targets.md")

    assert "docs/ops/multiqc_qc_targets.md" in readme
    for expected in (
        "produce_multiqc_seq_data",
        "produce_multiqc_alignment",
        "produce_multiqc_variants",
        "produce_multiqc_final",
        "runtime_gate_minutes: 45",
        'enable_tools=["fastv"]',
        "QC gap:",
    ):
        assert expected in doc
