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
        assert gate["include_no_dedup_contamination_qc"] is False
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
    assert '"site_mix"' not in common[common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")]
    assert "def qc_tool_enabled" in common
    assert "def qc_alignment_dedupers" in common
    assert "def qc_contamination_dedupers" in common
    assert "QC_CRAM_ALIGNERS=sorted(set(ALL_ALIGNERS)-set(BAM_ALIGNERS))" in common
    assert "VEP_CHRMS = [" in common
    assert "_day_chrm_token_to_contig(chrm)" in common
    assert "def get_vepchrm" in common
    assert "def get_vep_allowed_contigs" in common


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
    assert "qc_tool_enabled(\"site_mix\")" in text
    assert "qc_tool_enabled(\"vep\", long_running=True)" in text
    assert "qc_tool_enabled(\"snpeff\", long_running=True)" in text
    assert "QC_CRAM_ALIGNERS" in text
    assert "qc_alignment_dedupers()" in text
    assert "contamination_ddups = qc_contamination_dedupers()" in text
    assert (
        "alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv"
        in text
    )
    assert (
        "alignqc/contam/gatk/{sample}.{alnr}.{ddup}.gatk.tsv"
        in text
    )
    vb2_start = text.index("alignqc/contam/vb2/{vb2panel}")
    gatk_start = text.index("alignqc/contam/gatk/{sample}.{alnr}.{ddup}.gatk.tsv")
    assert "ddup=contamination_ddups" in text[vb2_start : vb2_start + 260]
    assert "ddup=contamination_ddups" in text[gatk_start : gatk_start + 220]
    assert '--ignore "*gatk_mqc.tsv"' in text
    assert '--ignore "*vb2_mqc.tsv"' in text
    assert "find {MDIR} -type f \\( -name '*gatk_mqc.tsv' -o -name '*vb2_mqc.tsv' \\) -delete" in text
    assert '--ignore "*/other_reports/logs/*"' in text
    for expected in (
        "sequence_qc_outputs_mqc.tsv",
        "alignment_qc_outputs_mqc.tsv",
        "contamination_mqc.tsv",
        "gatk_contam_mqc.tsv",
        "verifybamid2_panel_comparison_mqc.tsv",
        "site_mix_contam_mqc.tsv",
        "site_mix_donor_mqc.tsv",
        "bcftools_variant_stats_mqc.tsv",
        "peddy_sample_qc_mqc.tsv",
        "expansionhunter_mqc.tsv",
        "vep_annotation_mqc.tsv",
        "snpeff_annotation_mqc.tsv",
        "rules_benchmark_data_mqc.tsv",
        "workflow/scripts/build_multiqc_header.py",
    ):
        assert expected in text

    for removed in (
        'paths.append(MDIR + "other_reports/seqfu_mqc.tsv")',
        'paths.append(MDIR + "other_reports/relatedness_mqc.tsv")',
        'paths.append(MDIR + "other_reports/rtg_vcfstats_mqc.tsv")',
    ):
        assert removed not in text


def test_final_multiqc_custom_data_paths_match_outputs() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")
    sp = config["sp"]

    assert "verifybamid" in config["exclude_modules"]
    assert sp["norm_cov_evenness_combo"]["fn"] == (
        "other_reports/normcovevenness_combo_mqc.tsv"
    )

    expected_custom_paths = {
        "alignment_qc_outputs": "other_reports/alignment_qc_outputs_mqc.tsv",
        "alignstats_combo": "other_reports/alignstats_combo_mqc.tsv",
        "alignstats_gs": "other_reports/alignstats_gs_mqc.tsv",
        "bcftools_variant_stats": "other_reports/bcftools_variant_stats_mqc.tsv",
        "contamination": "other_reports/contamination_mqc.tsv",
        "gatk_contam": "other_reports/gatk_contam_mqc.tsv",
        "expansionhunter": "other_reports/expansionhunter_mqc.tsv",
        "giab_concordance": "other_reports/giab_concordance_mqc.tsv",
        "norm_cov_evenness_combo": "other_reports/normcovevenness_combo_mqc.tsv",
        "peddy_sample_qc": "other_reports/peddy_sample_qc_mqc.tsv",
        "rules_benchmark_data": "other_reports/rules_benchmark_data_mqc.tsv",
        "sequence_qc_outputs": "other_reports/sequence_qc_outputs_mqc.tsv",
        "site_mix_contam": "other_reports/site_mix_contam_mqc.tsv",
        "site_mix_donor": "other_reports/site_mix_donor_mqc.tsv",
        "vep_annotation": "other_reports/vep_annotation_mqc.tsv",
        "verifybamid2_panel_comparison": (
            "other_reports/verifybamid2_panel_comparison_mqc.tsv"
        ),
    }
    for custom_id, path in expected_custom_paths.items():
        assert custom_id in config["custom_data"]
        assert sp[custom_id]["fn"] == path


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


def test_norm_cov_evenness_gather_uses_declared_inputs() -> None:
    text = _read("workflow/rules/calc_coverage_eveness.smk")
    rule_text = text[text.index("rule produce_cov_uniformity:") :]

    assert "other_reports/logs/normcovevenness_combo.log" in rule_text
    assert "input_files=({input:q})" in rule_text
    assert "test -s \"$mqc\"" in rule_text
    assert "find results | grep norm_cov_eveness.mqc.tsv | head -n 1" not in rule_text
    assert "grep .norm_cov_eveness.mqc.tsv | parallel" not in rule_text


def test_contamination_and_relatedness_aggregates_are_wired() -> None:
    site_mix = _read("workflow/rules/site_mix_contam.smk")
    gatk_contam = _read("workflow/rules/gatk_contam.smk")
    verifybamid2_contam = _read("workflow/rules/verifybamid2_contam.smk")
    relatedness = _read("workflow/rules/relatedness_batch.smk")
    report_script = _read("workflow/scripts/relatedness_report.py")
    report_env = _yaml("workflow/envs/report.yaml")

    assert "rule contamination_mqc_gather:" in site_mix
    assert '_enabled_contam_qc_paths("gatk_contam", "gatk", "contam.tsv")' in site_mix
    assert '"method": "calculate_contamination"' in site_mix
    for expected in (
        "verifybamid2",
        "gatk",
        "site_mix",
        "contamination_mqc.tsv",
        "gatk_contam_mqc.tsv",
        "site_mix_contam_mqc.tsv",
        "site_mix_donor_mqc.tsv",
        "QC_CRAM_ALIGNERS",
        "qc_contamination_dedupers()",
    ):
        assert expected in site_mix
    assert "mqc         =" not in gatk_contam
    assert "output.mqc" not in gatk_contam
    assert "mqc=MDIR" not in verifybamid2_contam
    assert "output.mqc" not in verifybamid2_contam

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


def test_other_reports_logs_are_not_multiqc_custom_content_candidates() -> None:
    for path in (
        "workflow/rules/multiqc_final_wgs.smk",
        "workflow/rules/calc_coverage_eveness.smk",
        "workflow/rules/htd_calls.smk",
    ):
        text = _read(path)
        assert "other_reports/logs/" in text
        assert "other_reports/logs/sequence_qc_outputs_mqc.log" not in text
        assert "other_reports/logs/alignment_qc_outputs_mqc.log" not in text
        assert "other_reports/logs/normcovevenness_combo_mqc.log" not in text
        assert "other_reports/logs/htd_calls_mqc.log" not in text


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
    slurm_config = _yaml("config/day_profiles/slurm/templates/rule_config.yaml")

    assert "rule bcftools_variant_stats_gather:" in bcftools
    assert "bcftools_variant_stats_mqc.tsv" in bcftools
    assert "rule rtg_vcfstats_gather:" in rtg
    assert "rtg_vcfstats_mqc.tsv" in rtg
    assert "rule peddy_sample_qc_gather:" in peddy
    assert "peddy_sample_qc_mqc.tsv" in peddy
    assert "rule vep:" not in vep
    assert "rule vep_chromosome_input:" in vep
    assert "rule vep_chromosome:" in vep
    assert "rule vep_concat_fofn:" in vep
    assert "rule vep_concat_index_chunks:" in vep
    concat_fofn_rule = vep[
        vep.index("rule vep_concat_fofn:") : vep.index("rule vep_concat_index_chunks:")
    ]
    assert "tmp_fofn=MDIR" in concat_fofn_rule
    assert "{params.tmp_fofn}" in concat_fofn_rule
    assert "{output.tmp_fofn}" not in concat_fofn_rule
    concat_rule = vep[vep.index("rule vep_concat_index_chunks:") :]
    assert "ovcfgztemp=MDIR" in concat_rule
    assert "{params.ovcfgztemp}" in concat_rule
    assert "{output.ovcfgztemp}" not in concat_rule
    assert "--input_file {input.vcfgz}" not in vep
    assert "--input_file {input.chunk_vcfgz}" in vep
    assert "--chr {params.contig}" in vep
    assert "--assembly {params.genome_build}" in vep
    assert "--dir_cache {params.vep_cache}" in vep
    assert "--cache_version {params.cache_version}" in vep
    assert "--cache {params.vep_cache}" not in vep
    assert "--fork {threads}" in vep
    assert "threads: config[\"vep\"][\"threads\"]" in vep
    assert 'mem_mb=config["vep"].get("mem_mb", 3000)' in vep
    assert vep.count("cluster_sample=ret_sample") >= 3
    assert "vep.input_contigs.ok" in vep
    assert "bcftools concat -a -d all" in vep
    assert "does not match input chunk count" in vep
    assert "does not match input count" in vep
    assert slurm_config["vep"]["threads"] == 16
    assert slurm_config["vep"]["mem_mb"] == 64000
    assert slurm_config["vep"]["partition"] == "i192,i192mem,i128"
    assert slurm_config["vep"]["concat_threads"] == 16
    assert slurm_config["vep"]["concat_mem_mb"] == 32000
    assert slurm_config["vep"]["concat_partition"] == "i192,i192mem,i128"
    assert slurm_config["vep"]["hg38_vep_chrms"] == "1-25"
    assert slurm_config["vep"]["hg38_broad_vep_chrms"] == "1-25"
    assert slurm_config["vep"]["b37_vep_chrms"] == "1-25"
    assert "vep_annotation_mqc.tsv" in vep
    assert "valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)" in vep
    assert "bgzip -c > {output.annovcf}" in snpeff
    assert "snpeff_annotation_mqc.tsv" in snpeff


def test_multiqc_config_custom_content_entries() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")

    for key in (
        "sequence_qc_outputs",
        "alignment_qc_outputs",
        "contamination",
        "gatk_contam",
        "verifybamid2_panel_comparison",
        "site_mix_contam",
        "site_mix_donor",
        "bcftools_variant_stats",
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
    assert "verifybamid" in excludes
    assert "verifyBAMID" in excludes
    assert "sexdetermine" in excludes


def test_multiqc_sample_name_cleanup_contract() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")
    trim = set(config["extra_fn_clean_trim"])
    assert ".snv.sort.vcf.gz" in trim
    assert ".snv.sort.vcf.gz.tbi" in trim
    assert ".snv.sort" in trim
    assert ".idxstat.tsv" in trim
    assert ".idxstat" in trim
    assert ".mosdepth.summary.sort.bed" in trim
    assert ".mosdepth.summary.sort" in trim
    assert ".bcfstats.tsv" in trim
    assert config["sample_names_replace_regex"] is True
    assert config["sample_names_replace"][r"\.md\.(chr[0-9XYM]+)$"] == r".\1"

    module_order = config["module_order"]
    assert module_order == [
        "fastqc",
        "fastq_screen",
        "sequence_qc_outputs",
        "kat",
        "samtools",
        "bamtools",
        "qualimap",
        "sentieon",
        "alignstats_combo",
        "alignment_qc_outputs",
        "mosdepth",
        "goleft_indexcov",
        "picard",
        "norm_cov_evenness_combo",
        "peddy",
        "peddy_sample_qc",
        "somalier",
        "bcftools",
        "bcftools_variant_stats",
        "vcftools",
        "contamination",
        "verifybamid2_panel_comparison",
        "gatk_contam",
        "giab_concordance",
        "site_mix_contam",
        "site_mix_donor",
        "vep",
        "vep_annotation",
        "snpeff_annotation",
        "expansionhunter",
        "htd_calls",
        "rules_benchmark_data",
        "custom_content",
    ]
    assert "verifyBAMID" not in module_order
    assert "gatk_contam" in module_order
    assert "verifybamid2_panel_comparison" in module_order

    assert config["custom_content"]["order"] == [
        "sequence_qc_outputs",
        "alignstats_combo",
        "alignment_qc_outputs",
        "normcovevenness_combo",
        "peddy_sample_qc",
        "bcftools_variant_stats",
        "contamination",
        "verifybamid2_panel_comparison",
        "gatk_contam",
        "giab_concordance",
        "site_mix_contam",
        "site_mix_donor",
        "vep_annotation",
        "expansionhunter",
        "rules_benchmark_data",
    ]

    expected_section_order = [
        "general_stats",
        "fastqc",
        "sequence_qc_outputs",
        "samtools",
        "alignstats_combo",
        "alignment_qc_outputs",
        "mosdepth",
        "goleft_indexcov",
        "normcovevenness_combo",
        "peddy",
        "peddy_sample_qc",
        "somalier",
        "bcftools",
        "bcftools_variant_stats",
        "contamination",
        "verifybamid2_panel_comparison",
        "gatk_contam",
        "giab_concordance",
        "site_mix_contam",
        "site_mix_donor",
        "vep",
        "vep_annotation",
        "expansionhunter",
        "rules_benchmark_data",
        "multiqc_software_versions",
    ]
    section_order = config["report_section_order"]
    assert list(section_order) == expected_section_order
    assert [
        section_order[section_id]["order"] for section_id in expected_section_order
    ] == list(range(10000, 7500, -100))


def test_custom_multiqc_sample_ids_follow_pipeline_depth() -> None:
    common = _read("workflow/rules/common.smk")
    contamination = _read("workflow/rules/site_mix_contam.smk")
    bcftools = _read("workflow/rules/bcftools_vcfstat.smk")
    vep = _read("workflow/rules/vep.smk")

    assert "def day_stage_sample_id(sample, *components)" in common
    assert "day_stage_sample_id(sample, aligner, deduper)" in contamination
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in bcftools
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in vep
    assert "marker = f\".{alnr}.{ddup}.{caller}.\"" in bcftools
    assert "VEP_CHRMS = [" in common
    assert "_day_chrm_token_to_contig(chrm)" in common


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
        "site_mix genotype-free contamination",
        "QC gap:",
    ):
        assert expected in doc
