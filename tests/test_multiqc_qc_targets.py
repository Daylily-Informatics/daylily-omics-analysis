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
        'include: "rules/run_qc_reports.smk"',
        'include: "rules/truvari_sv_benchmark.smk"',
        'include: "rules/unmapped_metagenomics.smk"',
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
        "rule produce_multiqc_input_data:",
        "rule produce_multiqc_cram:",
        "rule produce_multiqc_snv:",
        "rule produce_multiqc_sv:",
        "rule produce_multiqc_sample_qc:",
        "rule produce_multiqc_variant_annotation:",
        "rule produce_multiqc_all:",
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
    assert "def _sv_component_inputs" in text
    assert 'qc_tool_enabled("fastp")' not in text
    assert "seqqc/fastp" not in text
    assert "qc_tool_enabled(\"fastv\", long_running=True)" in text
    assert "qc_tool_enabled(\"kat\", long_running=True)" in text
    assert "qc_tool_enabled(\"site_mix\")" in text
    assert "qc_tool_enabled(\"vep\", long_running=True)" in text
    assert "qc_tool_enabled(\"snpeff\", long_running=True)" in text
    assert "QC_CRAM_ALIGNERS" in text
    assert "qc_alignment_dedupers()" in text
    assert "qc_contamination_dedupers()" in text
    assert 'config.get("truvari_sv_benchmark", {}).get("truthsets")' in text
    assert '{"dysgu", "manta", "tiddit"}' in text
    for expected in (
        "sequence_qc_outputs_mqc.tsv",
        "alignment_qc_outputs_mqc.tsv",
        "contamination_mqc.tsv",
        "verifybamid2_panel_comparison_mqc.tsv",
        "site_mix_contam_mqc.tsv",
        "site_mix_donor_mqc.tsv",
        "relatedness_mqc.tsv",
        "bcftools_variant_stats_mqc.tsv",
        "rtg_vcfstats_mqc.tsv",
        "tiddit_sv_mqc.tsv",
        "giab_sv_concordance_mqc.tsv",
        "peddy_sample_qc_mqc.tsv",
        "expansionhunter_mqc.tsv",
        "vep_annotation_mqc.tsv",
        "snpeff_annotation_mqc.tsv",
        "rules_benchmark_data_mqc.tsv",
    ):
        assert expected in text


def test_sequence_qc_repairs_are_strict_and_multiqc_ready() -> None:
    fastqc = _read("workflow/rules/fastqc.smk")
    fastp = _read("workflow/rules/fastp.smk")
    fastv = _read("workflow/rules/fastv.smk")
    seqfu = _read("workflow/rules/seqfu.smk")
    multiqc = _read("config/external_tools/multiqc_config.yaml")

    assert "bench=MDIR" not in fastp
    assert ": > {log.a};" in fastp
    assert "{sample}.R1.fastq.gz" in fastqc
    assert "{sample}.R2.fastq.gz" in fastqc
    assert "{params.r1_link:q} {params.r2_link:q}" in fastqc
    assert "{input.fpqr1s}" in fastv
    assert "{input.fpqr2s}" in fastv
    assert "mkdir -p $(dirname {output});" in fastv
    assert "find {params.mdir} -name '*seqfuR1.mqc.tsv'" in seqfu
    assert "parallel" not in seqfu
    assert "other_reports/seqfu_mqc.tsv" in seqfu
    assert 'printf "Sample\\\\tbase_sample\\\\tread\\\\tsource_path\\\\n" > {output.mqc};' in seqfu
    assert 'printf "%s.R1\\\\t%s\\\\tR1\\\\t%s\\\\n"' in seqfu
    assert 'printf "%s.R2\\\\t%s\\\\tR2\\\\t%s\\\\n"' in seqfu
    assert "\n  - fastp\n" not in multiqc
    assert "\n  - giab_sv_concordance\n" in multiqc
    assert "giab_sv_concordance:" in multiqc
    assert "other_reports/giab_sv_concordance_mqc.tsv" in multiqc
    catalog = _read("docs/catalog_of_tools.md")
    assert "Native MultiQC SeqFu parsing is the intended replacement path once validated" in catalog


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
        "Sample",
        "base_sample",
        "stage",
        "tool",
        "source_path",
        "ALIGNQC_RE",
        "SEQQC_RE",
    ):
        assert expected in script


def test_multiqc_ignores_other_report_logs_and_custom_logs_avoid_mqc_suffix() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")
    htd = _read("workflow/rules/htd_calls.smk")

    assert text.count('--ignore "*/other_reports/logs/*"') >= 4
    assert text.count('--ignore "other_reports/logs/*"') >= 4
    assert text.count('--ignore "*_mqc.log"') >= 4
    assert text.count("workflow/scripts/multiqc_log_guard.py") >= 4
    assert text.count("multiqc --version") >= 4
    assert "docker://multiqc/multiqc:v1.35" in text
    assert "daylilyinformatics/daylily_multiqc:0.2" not in text
    assert "sequence_qc_outputs_custom_data.log" in text
    assert "alignment_qc_outputs_custom_data.log" in text
    assert "sequence_qc_outputs_mqc.log" not in text
    assert "alignment_qc_outputs_mqc.log" not in text
    assert "htd_calls_custom_data.log" in htd
    for rule_file in (REPO_ROOT / "workflow/rules").glob("*.smk"):
        rule_text = rule_file.read_text(encoding="utf-8")
        assert "sequence_qc_outputs_mqc.log" not in rule_text, rule_file
        assert "alignment_qc_outputs_mqc.log" not in rule_text, rule_file


def test_contamination_and_relatedness_aggregates_are_wired() -> None:
    site_mix = _read("workflow/rules/site_mix_contam.smk")
    contamination_script = _read("workflow/scripts/compile_contamination_mqc.py")
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
        "qc_contamination_dedupers()",
        "workflow/scripts/compile_contamination_mqc.py",
    ):
        assert expected in site_mix
    assert '"Sample",' in contamination_script
    assert '"base_sample",' in contamination_script
    assert '"sample_id": sample_id' not in contamination_script
    assert '"sample_id": sample' in contamination_script

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
    tiddit = _read("workflow/rules/tiddit.smk")
    slurm_config = _yaml("config/day_profiles/slurm/templates/rule_config.yaml")

    assert "rule bcftools_variant_stats_gather:" in bcftools
    assert "bcftools_variant_stats_mqc.tsv" in bcftools
    assert "rule rtg_vcfstats_gather:" in rtg
    assert "rtg_vcfstats_mqc.tsv" in rtg
    assert "rule tiddit_sv_mqc_gather:" in tiddit
    assert "workflow/scripts/tiddit_sv_to_multiqc.py" in tiddit
    assert "tiddit_sv_mqc.tsv" in tiddit
    assert 'if "tiddit" not in sv_CALLERS:' in tiddit
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
    assert slurm_config["rtg_vcfeval"]["mem_mb"] == 64000
    assert slurm_config["rtg_vcfeval"]["parse_mem_mb"] == 16000
    assert "vep_annotation_mqc.tsv" in vep
    assert "valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)" in vep
    assert "bgzip -c > {output.annovcf}" in snpeff
    assert "snpeff_annotation_mqc.tsv" in snpeff


def test_multiqc_config_custom_content_entries() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")

    for key in (
        "seqfu",
        "sequence_qc_outputs",
        "bclconvert_demux",
        "bclconvert_lane_summary",
        "bclconvert_fastq_manifest",
        "bclconvert_unknown_barcodes",
        "bclconvert_index_hopping",
        "alignment_qc_outputs",
        "contamination",
        "verifybamid2_panel_comparison",
        "site_mix_contam",
        "site_mix_donor",
        "relatedness",
        "bcftools_variant_stats",
        "rtg_vcfstats",
        "tiddit_sv",
        "peddy_sample_qc",
        "vep_annotation",
        "snpeff_annotation",
        "htd_calls",
        "expansionhunter",
    ):
        assert key in config["custom_data"]
        assert key in config["sp"]
        assert "parent_id" in config["custom_data"][key]
        assert "parent_name" in config["custom_data"][key]

    excludes = set(config["exclude_modules"])
    assert "fastp" not in excludes
    assert "vep" not in excludes
    assert "snpeff" not in excludes
    assert "peddy" not in excludes
    assert "somalier" not in excludes
    assert "verifyBAMID" not in excludes
    assert "sexdetermine" in excludes

    parents = {
        custom["parent_name"]
        for custom in config["custom_data"].values()
        if "parent_name" in custom
    }
    assert "Input, demux, read QC, trimming" in parents
    assert "Alignment, BAM/CRAM, dedup, coverage" in parents
    assert "Variant, genotype, benchmark, annotation" in parents
    assert "Proteomics, workflow, misc" in parents
    section_order = config["report_section_order"]
    assert section_order["fastqc"]["order"] < section_order["samtools"]["order"]
    assert section_order["samtools"]["order"] < section_order["peddy"]["order"]
    assert section_order["peddy"]["order"] < section_order["bcftools"]["order"]


def test_multiqc_sample_name_cleanup_contract() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")
    trim = set(config["extra_fn_clean_trim"])
    assert ".snv.sort.vcf.gz" in trim
    assert ".snv.sort.vcf.gz.tbi" in trim
    assert ".R1.fastq.gz" not in trim
    assert ".R2.fastq.gz" not in trim
    assert ".R1.fastq" not in trim
    assert ".R2.fastq" not in trim
    assert ".snv.sort" in trim
    assert ".idxstat.tsv" in trim
    assert ".idxstat" in trim
    assert ".mosdepth.summary.sort.bed" in trim
    assert ".mosdepth.summary.sort" in trim
    assert ".bcfstats.tsv" in trim
    for picard_suffix in (
        ".alignment_summary_metrics.txt",
        ".insert_size_metrics.txt",
        ".quality_yield_metrics.txt",
        ".quality_distribution_metrics.txt",
        ".gc_bias.summary_metrics.txt",
        ".gc_bias.detail_metrics.txt",
    ):
        assert picard_suffix in trim
    assert ".rtg.vcfstats.txt" in trim
    assert ".verifybamid.selfSM" in trim
    assert ".peddy.sex_check.csv" in trim
    assert ".peddy.het_check.csv" in trim
    assert ".peddy.ped_check.csv" in trim
    assert ".legacy_compat.bam" in trim
    filename_modules = set(config["use_filename_as_sample_name"])
    for module in (
        "samtools",
        "picard",
        "mosdepth",
        "verifybamid",
        "peddy",
        "somalier",
        "bcftools",
    ):
        assert module in filename_modules
    assert config["sample_names_replace_regex"] is True
    assert config["sample_names_replace"][r"\.md\.(chr[0-9XYM]+)$"] == r".\1"
    assert config["sample_names_replace"][r"\.metrics$"] == ""
    assert config["sample_names_replace"][r"_FR$"] == ""
    assert (
        config["sample_names_replace"][
            r"^(.*)-([A-Za-z0-9_]+)-(dmd|smd|spmd|na)-cram$"
        ]
        == r"\1.\2.\3"
    )

    module_order = config["module_order"]
    assert len(module_order) == len(set(module_order))
    assert all(entry == entry.strip() for entry in module_order)
    assert "peddy" in module_order
    assert "somalier" in module_order
    assert "peddy_sample_qc" in module_order
    assert "relatedness" in module_order
    assert "verifyBAMID" not in module_order
    assert "verifybamid2_panel_comparison" in module_order


def test_multiqc_reports_scan_only_staged_inputs() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")

    assert "rule stage_multiqc_inputs:" in text
    assert "workflow/scripts/stage_multiqc_inputs.py" in text
    assert "workflow/scripts/validate_multiqc_sample_ids.py" in text
    assert "reports/multiqc_inputs/seq_data" in text
    assert "reports/multiqc_inputs/alignment" in text
    assert "reports/multiqc_inputs/variants" in text
    assert "reports/multiqc_inputs/final" in text
    assert "--input-root {params.input_root:q}" in text
    for rule_name, stage in (
        ("rule multiqc_seq_data:", "seq_data"),
        ("rule multiqc_alignment:", "alignment"),
        ("rule multiqc_variants:", "variants"),
        ("rule multiqc_final_wgs:", "final"),
    ):
        body = text[text.index(rule_name) :]
        next_rule = body.find("\n\nrule ", 1)
        if next_rule != -1:
            body = body[:next_rule]
        assert f'stage_dir=MDIR + "reports/multiqc_inputs/{stage}"' in body
        assert "{params.stage_dir:q}" in body
        assert "{MDIR} > {log:q}" not in body
        assert "{MDIR} >> {log:q}" not in body


def test_custom_multiqc_sample_ids_follow_pipeline_depth() -> None:
    common = _read("workflow/rules/common.smk")
    contamination = _read("workflow/rules/site_mix_contam.smk")
    contamination_script = _read("workflow/scripts/compile_contamination_mqc.py")
    bcftools = _read("workflow/rules/bcftools_vcfstat.smk")
    rtg_vcfstats = _read("workflow/rules/rtg_vcfstats.smk")
    peddy = _read("workflow/rules/peddy.smk")
    vep = _read("workflow/rules/vep.smk")
    snpeff = _read("workflow/rules/snpeff.smk")

    assert "def day_stage_sample_id(sample, *components)" in common
    assert "_stage_sample_id(sample, aligner, deduper)" in contamination_script
    assert "qc_contamination_dedupers()" in contamination
    assert '"base_sample": sample' in contamination_script
    assert '"sample_id": sample,' in contamination_script
    assert "compile_contamination_mqc.py" in contamination
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in bcftools
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in rtg_vcfstats
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in peddy
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in vep
    assert "day_stage_sample_id(sample, aligner, deduper, caller)" in snpeff
    assert "marker = f\".{alnr}.{ddup}.{caller}.\"" in bcftools
    assert "VEP_CHRMS = [" in common
    assert "_day_chrm_token_to_contig(chrm)" in common


def test_contamination_rules_do_not_emit_per_sample_custom_content_tsvs() -> None:
    verifybamid2 = _read("workflow/rules/verifybamid2_contam.smk")
    gatk = _read("workflow/rules/gatk_contam.smk")
    multiqc_final = _read("workflow/rules/multiqc_final_wgs.smk")

    assert "qc_contamination_dedupers()" in verifybamid2
    assert "qc_contamination_dedupers()" in gatk
    assert "vb2_mqc.tsv" not in verifybamid2.split("output:", 1)[1].split("log:", 1)[0]
    assert "gatk_mqc.tsv" not in gatk.split("output:", 1)[1].split("log:", 1)[0]
    assert "{params.old_mqc}" in verifybamid2
    assert "{params.old_mqc}" in gatk
    assert multiqc_final.count('--ignore "*vb2_mqc.tsv"') >= 4
    assert multiqc_final.count('--ignore "*gatk_mqc.tsv"') >= 4


def test_multiqc_runtime_policy_documented() -> None:
    readme = _read("README.md")
    doc = _read("docs/ops/multiqc_qc_targets.md")

    assert "docs/ops/multiqc_qc_targets.md" in readme
    for expected in (
        "produce_multiqc_seq_data",
        "produce_multiqc_alignment",
        "produce_multiqc_variants",
        "produce_multiqc_final",
        "produce_multiqc_input_data",
        "produce_multiqc_cram",
        "produce_multiqc_snv",
        "produce_multiqc_sv",
        "produce_multiqc_sample_qc",
        "produce_multiqc_variant_annotation",
        "produce_multiqc_all",
        "runtime_gate_minutes: 45",
        'enable_tools=["fastv"]',
        "site_mix genotype-free contamination",
        "reports/multiqc_inputs/<stage>/",
        "Duplicate `(module, Sample)` pairs fail during staging",
        "`<sample>.<aligner>.<deduper>.<snv_caller>`",
        "`<sample>.<aligner>.<deduper>.<sv_caller>`",
        "Peddy CSVs and VerifyBamID `.selfSM` files are rewritten",
        "`parent_id` / `parent_name` grouping",
        "QC gap:",
    ):
        assert expected in doc

    catalog = _read("docs/catalog_of_tools.md")
    assert "stage-scoped sample identity" in catalog
    assert "stage_multiqc_inputs.py" in catalog
    assert "validate_multiqc_sample_ids.py" in catalog
