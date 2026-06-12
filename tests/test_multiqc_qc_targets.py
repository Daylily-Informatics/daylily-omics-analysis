from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
MULTIQC_ENV_YAML = "../envs/multiqc_v0.1.yaml"


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def _localrules_entries(text: str) -> set[str]:
    marker = "localrules:"
    assert marker in text
    block = text[text.index(marker) + len(marker) : text.index("rule write_dayoa_evidence_manifest:")]
    entries = set()
    for line in block.splitlines():
        stripped = line.strip().rstrip(",")
        if stripped:
            entries.add(stripped)
    return entries


def _rule_block(text: str, rule_name: str) -> str:
    marker = f"rule {rule_name}:"
    assert marker in text, rule_name
    start = text.index(marker)
    next_start = text.find("\nrule ", start + len(marker))
    if next_start == -1:
        return text[start:]
    return text[start:next_start]


def test_benchmark_collection_rules_do_not_introduce_benchmark_only_wildcards() -> None:
    final_wgs = _read("workflow/rules/multiqc_final_wgs.smk")
    singleton = _read("workflow/rules/multiqc_singleton.smk")

    for text, rule_name in (
        (final_wgs, "collect_rules_benchmark_data"),
        (final_wgs, "collect_rules_benchmark_data_singleton"),
        (singleton, "collect_rules_benchmark_data2"),
    ):
        block = _rule_block(text, rule_name)
        benchmark_line = next(
            line.strip()
            for line in block.splitlines()
            if line.strip().endswith(f"{rule_name}.bench.tsv\"")
        )
        assert "benchmarks/{MDIR}." not in benchmark_line
        assert f"{rule_name}.bench.tsv" in block


def test_target_wrapper_rules_do_not_introduce_log_only_wildcards() -> None:
    dedup = _read("workflow/rules/generate_deduplicated_bams.smk")
    final_wgs = _read("workflow/rules/multiqc_final_wgs.smk")

    for text, rule_name in (
        (dedup, "produce_deduplicated_crams"),
        (dedup, "dedup_doppelmark"),
        (dedup, "dedup_sentieon"),
        (dedup, "dedup_none"),
        (final_wgs, "aggregate_report_components"),
    ):
        block = _rule_block(text, rule_name)
        log_block = block.split("log:", 1)[1].split("benchmark:", 1)[0].split("shell:", 1)[0]
        benchmark_block = (
            block.split("benchmark:", 1)[1].split("shell:", 1)[0]
            if "benchmark:" in block
            else ""
        )
        assert "{sample}" not in log_block
        assert "{alnr}" not in log_block
        assert "{ddup}" not in log_block
        assert "{MDIR}" not in log_block
        assert "{sample}" not in benchmark_block
        assert "{alnr}" not in benchmark_block
        assert "{ddup}" not in benchmark_block
        assert "{MDIR}" not in benchmark_block


def test_snakefile_includes_repaired_qc_rules() -> None:
    snakefile = _read("workflow/Snakefile")
    active_includes = [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]

    assert 'include: "rules/fastp.smk"' not in snakefile
    assert 'include: "rules/fastv.smk"' not in active_includes
    assert "workflow/rules/archived_qc/fastv.smk" in snakefile
    assert "workflow/rules/archived_qc/verifybamid2_contam.smk" in snakefile
    assert 'include: "rules/picard.smk"' not in active_includes
    assert '# include: "rules/picard.smk"' in snakefile
    assert 'include: "rules/qualimap.smk"' not in active_includes
    assert '# include: "rules/qualimap.smk"' in snakefile
    assert 'include: "rules/gauchian.smk"' in active_includes
    assert "Historical alternate GBA integration" in snakefile
    assert 'include: "rules/parascopy.smk"' not in active_includes
    assert '# include: "rules/parascopy.smk"' in snakefile
    assert 'include: "rules/hapsma.smk"' in active_includes
    assert 'include: "rules/sma_finder.smk"' in active_includes
    assert 'include: "rules/smaca.smk"' in active_includes
    assert 'include: "rules/smn12_orthogonal_calls.smk"' in active_includes
    assert 'include: "rules/smn_copynumbercaller.smk"' in active_includes
    assert 'include: "rules/genetocn.smk"' not in active_includes
    assert '# include: "rules/genetocn.smk"' in snakefile
    assert "alignqc/picard" not in _read("workflow/rules/multiqc_final_wgs.smk")
    assert "alignqc/picard" not in _read("workflow/rules/multiqc_cov_aln.smk")
    assert "alignqc/qmap" not in _read("workflow/rules/multiqc_final_wgs.smk")
    assert "alignqc/qmap" not in _read("workflow/rules/multiqc_cov_aln.smk")
    for include in (
        'include: "rules/seqfu.smk"',
        'include: "rules/relatedness_batch.smk"',
        'include: "rules/contam_identity.smk"',
        'include: "rules/longtr.smk"',
        'include: "rules/run_qc_reports.smk"',
        'include: "rules/truvari_sv_benchmark.smk"',
        'include: "rules/unmapped_metagenomics.smk"',
    ):
        assert include in snakefile


def test_snakefile_active_rule_includes_are_ordered_with_dependency_exceptions() -> None:
    snakefile = _read("workflow/Snakefile")
    block = snakefile.split("# Rule imports.", 1)[1].split("# #### A FEW FUSSY THINGS", 1)[0]
    active_includes = [
        line.strip().split('"')[1]
        for line in block.splitlines()
        if line.strip().startswith("include:")
    ]

    dependency_exceptions = {
        "rules/contam_identity.smk",
        "rules/legacy_cram_compat_bam.smk",
        "rules/site_mix_contam.smk",
    }
    assert active_includes.index("rules/legacy_cram_compat_bam.smk") < active_includes.index(
        "rules/contam_identity.smk"
    )
    assert active_includes.index("rules/site_mix_contam.smk") < active_includes.index(
        "rules/contam_identity.smk"
    )
    assert [item for item in active_includes if item not in dependency_exceptions] == [
        item
        for item in sorted(active_includes, key=str.casefold)
        if item not in dependency_exceptions
    ]


def test_retired_fastv_and_verifybamid2_rules_are_archived_only() -> None:
    snakefile = _read("workflow/Snakefile")
    active_includes = [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]

    assert (REPO_ROOT / "workflow/rules/archived_qc/fastv.smk").exists()
    assert (REPO_ROOT / "workflow/rules/archived_qc/verifybamid2_contam.smk").exists()
    assert not (REPO_ROOT / "workflow/rules/fastv.smk").exists()
    assert not (REPO_ROOT / "workflow/rules/verifybamid2_contam.smk").exists()
    assert 'include: "rules/fastv.smk"' not in active_includes
    assert 'include: "rules/archived_qc/fastv.smk"' not in active_includes
    assert 'include: "rules/verifybamid2_contam.smk"' not in active_includes
    assert 'include: "rules/archived_qc/verifybamid2_contam.smk"' not in active_includes

    active_rule_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((REPO_ROOT / "workflow/rules").glob("*.smk"))
    )
    for retired_output_token in (
        "seqqc/fastv",
        "fastv.done",
        "fastv.json",
        "fastv.html",
        "alignqc/contam/vb2",
        "vb2.tsv",
        "vb2_mqc.tsv",
        "verifybamid2_panel_comparison_mqc.tsv",
        "contam_identity/charr",
        "charr_mqc.tsv",
        "rule charr_contam_identity:",
        "rule produce_charr_contam_identity:",
    ):
        assert retired_output_token not in active_rule_text
    assert not (REPO_ROOT / "workflow/envs/charr_v0.1.yaml").exists()
    assert not (REPO_ROOT / "workflow/scripts/run_charr_contam.py").exists()


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
        assert config["contam_identity"]["primary_snv_caller"] == "sentd"
        assert "ngstroublefinder" not in config
        assert "charr" not in config
        for section in ("haplocheck", "read_haps"):
            assert section in config
            assert config[section]["env_yaml"].startswith("../envs/")
            assert config[section]["partition"]
        assert config["haplocheck"]["input_modes"] == ["vcf"]
        if path == "config/day_profiles/slurm/templates/rule_config.yaml":
            assert config["haplocheck"]["threads"] == 96
            assert config["haplocheck"]["partition"] == "i192"
        assert config["read_haps"]["read_haps_command"].endswith("/read_haps/read_haps")
        assert config["read_haps"]["reliable_snp_file"].endswith(
            "high_quality_markers_deCODE_2015.txt.gz"
        )
        metagenomics = config["unmapped_metagenomics"]
        assert metagenomics["kraken2_db"].endswith(
            "metagenomics/kraken2/k2_pluspfp_16_GB_20260226"
        )
        assert metagenomics["ganon2_db_prefixes"] == [
            "/fsx/references/runtime_assets/tool_specific_resources/ganon2/"
            "dayoa_qc_refseq_abfv_complete_top1_20260528"
        ]
        assert metagenomics["sourmash_databases"] == [
            "/fsx/references/runtime_assets/tool_specific_resources/sourmash/"
            "gtdb-rs226/gtdb-reps-rs226-k31.dna.zip"
        ]
        assert metagenomics["read_limit"] == "all"
        assert metagenomics["threads"] >= 16
        longtr = config["longtr"]
        assert longtr["command"] == "LongTR"
        assert longtr["aligners"] == ["ont", "sentmm2ont"]
        assert longtr["deduper"] == "na"
        assert longtr["catalogs"]["all"]["regions_bed"].endswith(
            "longtr/trexplorer_catalog/"
            "TRExplorer.repeat_catalog_v2.hg38.1_to_1000bp_motifs.LongTR.bed.gz"
        )
        assert longtr["catalogs"]["diseaser"]["regions_bed"].endswith(
            "longtr/disease_repeat_catalog/"
            "dayoa_STRchive-disease-loci.hg38.longtr.bed.gz"
        )
        truvari = config["truvari_sv_benchmark"]
        hg002 = truvari["truthsets"]["HG002"]["regions"]["giab_sv_v5_0q_hc"]
        assert truvari["truthsets"]["HG002"]["alt_id"] == "HG002"
        assert hg002["truth_vcf"].endswith("HG002_GRCh38_v5.0q_stvar.vcf.gz")
        assert hg002["truth_tbi"].endswith("HG002_GRCh38_v5.0q_stvar.vcf.gz.tbi")
        assert hg002["truth_bed"].endswith("HG002_GRCh38_v5.0q_stvar.benchmark.bed")


def test_common_declares_runtime_gate_helpers_and_cram_qc_scope() -> None:
    common = _read("workflow/rules/common.smk")

    assert "MULTIQC_QC_LONG_RUNNING_TOOLS" in common
    for tool in ("vep", "contam_identity"):
        assert f'"{tool}"' in common
    assert '"fastv"' not in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert '"snpeff"' not in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert '"kat"' not in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert '"site_mix"' not in common[common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")]
    assert "def qc_tool_enabled" in common
    assert "def qc_alignment_dedupers" in common
    assert "def qc_contamination_dedupers" in common
    assert "QC_CRAM_ALIGNERS=sorted(set(ALL_ALIGNERS)-set(BAM_ALIGNERS)-GRAPH_ONLY_PANGENOME_ALIGNERS)" in common
    assert "def smn_short_cram" in common
    assert "def smn_long_cram" in common
    assert "sentdhiomr.sr_dedup.cram" in common
    assert "_sentdhiomr_lr_cram(wildcards)" in common
    assert "VEP_CHRMS = [" in common
    assert "_day_chrm_token_to_contig(chrm)" in common
    assert "def get_vepchrm" in common
    assert "def get_vep_allowed_contigs" in common


def test_goleft_indexcov_disables_sex_chromosome_expectation() -> None:
    goleft = _read("workflow/rules/go_left.smk")

    assert 'sexchrms=""' in goleft
    assert 'if [[ -n "$sexchrms" ]]; then' in goleft
    assert 'sex_args=(--sex "$sexchrms")' in goleft
    assert 'goleft indexcov --directory $gl "${{sex_args[@]}}"' in goleft
    assert "--sex {params.sexchrms} " not in goleft
    assert "chrX,chrY" not in goleft
    assert '"X,Y"' not in goleft


def test_staged_multiqc_targets_and_dependencies_exist() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")
    evidence = _read("workflow/rules/evidence_manifest.smk")
    snakefile = _read("workflow/Snakefile")
    common = _read("workflow/rules/common.smk")

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
    assert "FASTQ_QC_SAMPS = [sample for sample in SAMPS if sample_has_fastq_qc_inputs(sample)]" in common
    assert common.index("SAMPS = list(get_samp_ids())") < common.index("FASTQ_QC_SAMPS =")
    assert 'qc_tool_enabled("fastp")' not in text
    assert "seqqc/fastp" not in text
    assert "qc_tool_enabled(\"fastv\", long_running=True)" not in text
    assert "seqqc/fastv" not in text
    assert "qc_tool_enabled(\"kat\"" not in text
    assert "seqqc/kat" not in text
    assert 'include: "rules/kat.smk"' not in [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]
    assert '# include: "rules/kat.smk"' in snakefile
    assert "sample=FASTQ_QC_SAMPS" in text
    seq_inputs = text[text.index("def _sequence_qc_native_inputs") : text.index("def _alignment_component_inputs")]
    assert "sample=SAMPS" not in seq_inputs
    assert "qc_tool_enabled(\"site_mix\")" in text
    assert "contam_identity_multiqc_inputs(wildcards)" in text
    assert "_contam_identity_native_inputs(wildcards)" in text
    for expected in (
        'data_json=MDIR + "reports/DAY_final_multiqc_data/multiqc_data.json"',
        'data_general_stats=MDIR + "reports/DAY_final_multiqc_data/multiqc_general_stats.txt"',
        'data_sources=MDIR + "reports/DAY_final_multiqc_data/multiqc_sources.txt"',
        'data_log=MDIR + "reports/DAY_final_multiqc_data/multiqc.log"',
    ):
        assert expected in text
    assert "qc_tool_enabled(\"vep\", long_running=True)" in text
    assert "qc_tool_enabled(\"snpeff\", long_running=True)" not in text
    assert "expansionhunter_report_targets_available()" in text
    assert "QC_CRAM_ALIGNERS" in text
    assert "qc_alignment_dedupers()" in text
    assert "qc_contamination_dedupers()" in text
    assert 'config.get("truvari_sv_benchmark", {}).get("truthsets")' in text
    assert '{"dysgu", "manta", "tiddit"}' in text
    for expected in (
        "input_sample_libraries_mqc.tsv",
        "sequence_qc_outputs_mqc.tsv",
        "alignment_qc_outputs_mqc.tsv",
        "contamination_mqc.tsv",
        "site_mix_contam_mqc.tsv",
        "site_mix_donor_mqc.tsv",
        "contam_identity_mqc.tsv",
        "haplocheck_mtdna_mqc.tsv",
        "read_haps_mqc.tsv",
        "relatedness_mqc.tsv",
        "bcftools_variant_stats_mqc.tsv",
        "rtg_vcfstats_mqc.tsv",
        "tiddit_sv_mqc.tsv",
        "giab_sv_concordance_mqc.tsv",
        "peddy_sample_qc_mqc.tsv",
        "expansionhunter_mqc.tsv",
        "vep_annotation_mqc.tsv",
        "rules_benchmark_data_mqc.tsv",
    ):
        assert expected in text
    assert "snpeff_annotation_mqc.tsv" not in text
    assert '# include: "rules/snpeff.smk"' in snakefile
    assert 'include: "rules/snpeff.smk"' not in [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]
    assert 'include: "rules/evidence_manifest.smk"' in snakefile
    assert 'include: "rules/qeo_registration.smk"' not in snakefile
    assert 'MDIR + "reports/dayoa_evidence_manifest.json"' in text
    for expected in (
        "rule write_dayoa_evidence_manifest:",
        "rule produce_dayoa_evidence_manifest:",
        "dayoa_evidence_manifest.json",
    ):
        assert expected in evidence

    for forbidden in (
        "dewey_receipt",
        "qeo_manifest",
        "qeo_ingest_manifest",
        "publish_qeo_ingest_event",
    ):
        assert forbidden not in evidence

    assert _localrules_entries(evidence) >= {
        "write_dayoa_evidence_manifest",
        "produce_dayoa_evidence_manifest",
    }


def test_sequence_qc_repairs_are_strict_and_multiqc_ready() -> None:
    fastqc = _read("workflow/rules/fastqc.smk")
    fastp = _read("workflow/rules/fastp.smk")
    fastv = _read("workflow/rules/archived_qc/fastv.smk")
    seqfu = _read("workflow/rules/seqfu.smk")
    multiqc = _read("config/external_tools/multiqc_config.yaml")
    slurm_config = _yaml("config/day_profiles/slurm/templates/rule_config.yaml")

    assert "bench=MDIR" not in fastp
    assert ": > {log.a};" in fastp
    assert 'mem_mb=config["fastqc"]["mem_mb"]' in fastqc
    assert slurm_config["fastqc"]["mem_mb"] == 64000
    assert 'lane_suffix=".${{lane_idx}}"' in fastqc
    assert "${{sample_name}}.R1${{lane_suffix}}.fastq.gz" in fastqc
    assert "${{sample_name}}.R2${{lane_suffix}}.fastq.gz" in fastqc
    assert "get_raw_fastq_qc_R1s" in fastqc
    assert "get_raw_fastq_qc_R2s" in fastqc
    assert "SKIP: fastqc_subsampled found no paired FASTQ inputs" in fastqc
    assert "sample=FASTQ_QC_SAMPS" in fastqc
    assert "fastqc_inputs=()" in fastqc
    assert "fastqc_subsampled requires matched R1/R2 FASTQ counts" in fastqc
    assert "expects exactly one R1 and one R2" not in fastqc
    assert "get_raw_fastq_qc_R1s" in seqfu
    assert "sample=FASTQ_QC_SAMPS" in seqfu
    assert "SKIP: seqfu found no paired FASTQ inputs" in seqfu
    assert "get_raw_fastq_qc_R1s" in fastv
    assert "sample=FASTQ_QC_SAMPS" in fastv
    assert "SKIP: fastv found no paired FASTQ inputs" in fastv
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
    assert "\n  - input_sample_libraries\n" in multiqc
    assert "other_reports/input_sample_libraries_mqc.tsv" in multiqc
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
        "rule input_sample_libraries_custom_data:",
        "rule sequence_qc_outputs_custom_data:",
        "rule alignment_qc_outputs_custom_data:",
        "workflow/scripts/multiqc_custom_output_inventory.py",
        "input_sample_libraries_mqc.tsv",
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
    assert f'conda:\n        "{MULTIQC_ENV_YAML}"' in text
    assert "docker://multiqc" not in "\n".join(
        rule_file.read_text(encoding="utf-8")
        for rule_file in (REPO_ROOT / "workflow/rules").glob("*.smk")
    )
    assert "daylilyinformatics/daylily_multiqc:0.2" not in text
    assert "workflow/scripts/force_multiqc_dark_mode.py" in text
    assert "DAY_final_multiqc.original.html" in text
    assert "--backup {output.html_original:q}" in text
    assert "sequence_qc_outputs_custom_data.log" in text
    assert "alignment_qc_outputs_custom_data.log" in text
    assert "sequence_qc_outputs_mqc.log" not in text
    assert "alignment_qc_outputs_mqc.log" not in text
    assert "htd_calls_custom_data.log" in htd
    for rule_file in (REPO_ROOT / "workflow/rules").glob("*.smk"):
        rule_text = rule_file.read_text(encoding="utf-8")
        assert "sequence_qc_outputs_mqc.log" not in rule_text, rule_file
        assert "alignment_qc_outputs_mqc.log" not in rule_text, rule_file


def test_multiqc_command_rules_use_dedicated_conda_env() -> None:
    bclconvert = _read("workflow/rules/bclconvert.smk")
    run_qc = _read("workflow/rules/run_qc_reports.smk")

    assert f'MULTIQC_ENV = "{MULTIQC_ENV_YAML}"' in bclconvert
    assert f'RUNQC_MULTIQC_ENV = "{MULTIQC_ENV_YAML}"' in run_qc

    rule_specs = (
        (
            "workflow/rules/multiqc_final_wgs.smk",
            (
                "multiqc_seq_data",
                "multiqc_alignment",
                "multiqc_variants",
                "multiqc_final_wgs",
            ),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/multiqc_singleton.smk",
            ("multiqc_singleton",),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/multiqc_for_raw_fastqs.smk",
            ("multiqc_for_raw_fastqs",),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/multiqc_cov_aln.smk",
            ("multiqc_cov_aln",),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/multiqc_for_bcl2fq.smk",
            ("multiqc_bcl2fq",),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/expansionhunter.smk",
            ("expansionhunter_multiqc",),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/unmapped_metagenomics.smk",
            (
                "unmapped_metagenomics_multiqc",
                "unmapped_metagenomics_ganon2_multiqc",
                "unmapped_metagenomics_sourmash_multiqc",
            ),
            f'conda:\n        "{MULTIQC_ENV_YAML}"',
        ),
        (
            "workflow/rules/bclconvert.smk",
            ("multiqc_bclconvert",),
            "conda:\n        MULTIQC_ENV",
        ),
        (
            "workflow/rules/run_qc_reports.smk",
            (
                "illumina_run_qc_multiqc",
                "ont_run_qc_multiqc",
                "ont_demux_fastq_multiqc",
            ),
            "conda:\n        RUNQC_MULTIQC_ENV",
        ),
    )

    for path, rule_names, expected_conda in rule_specs:
        text = _read(path)
        for rule_name in rule_names:
            block = _rule_block(text, rule_name)
            assert "multiqc " in block or "multiqc\t" in block, rule_name
            assert expected_conda in block, rule_name
            assert "container:" not in block, rule_name
            assert "docker://multiqc" not in block, rule_name


def test_contamination_and_relatedness_aggregates_are_wired() -> None:
    site_mix = _read("workflow/rules/site_mix_contam.smk")
    contamination_script = _read("workflow/scripts/compile_contamination_mqc.py")
    contam_identity = _read("workflow/rules/contam_identity.smk")
    identity_script = _read("workflow/scripts/compile_contam_identity_mqc.py")
    relatedness = _read("workflow/rules/relatedness_batch.smk")
    report_script = _read("workflow/scripts/relatedness_report.py")
    report_env = _yaml("workflow/envs/report.yaml")

    assert "rule contamination_mqc_gather:" in site_mix
    for expected in (
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
    assert "verifybamid2" not in contamination_script.lower()

    for expected in (
        "rule haplocheck_bam_contam_identity:",
        "rule haplocheck_vcf_contam_identity:",
        "rule read_haps_contam_identity:",
        "rule contam_identity_mqc_gather:",
        "rule produce_global_contam_check:",
        "contam_identity.primary_snv_caller",
        "Haplocheck",
        "read_haps",
    ):
        assert expected in contam_identity
    for retired in (
        "rule ngstroublefinder_contam_identity:",
        "rule produce_ngstroublefinder_contam_identity:",
        "ngstroublefinder_mqc.tsv",
        "rule charr_contam_identity:",
        "rule produce_charr_contam_identity:",
        "charr_mqc.tsv",
        "CHARR",
    ):
        assert retired not in contam_identity
    assert 'result_prefix="$result_dir/contamination.txt"' in contam_identity
    assert '{params.command:q} --out "$result_prefix" --raw {input.vcf:q}' in contam_identity
    assert "{params.command:q} --threads" not in contam_identity
    assert "export HAPLOCHECK_THREADS={threads}" in contam_identity
    assert "-XX:ActiveProcessorCount={threads}" in contam_identity
    assert "-XX:ParallelGCThreads={threads}" in contam_identity
    assert "-Djava.util.concurrent.ForkJoinPool.common.parallelism={threads}" in contam_identity
    assert "{params.cloudgene:q} run {params.app:q}" in contam_identity
    assert "--threads {threads}" in contam_identity
    assert 'cp "$result_dir/contamination.html" {output.html:q}' in contam_identity
    for expected in (
        "IDENTITY_FIELDS",
        "READ_HAPS_FIELDS",
        "PASS_FAIL",
        "tool_pass_fail",
        "mtdna_contamination_proxy",
        "ngstroublefinder",
        "haplocheck",
    ):
        assert expected in identity_script
    assert "charr" not in identity_script.lower()

    for expected in (
        "rule relatedness_batch_manifest:",
        "rule relatedness_batch_somalier_extract:",
        "rule relatedness_batch_somalier_relate:",
        "rule relatedness_batch_report:",
        "rule relatedness_batch_gather:",
        "rule produce_relatedness:",
        "relatedness_mqc.tsv",
        "QC_CRAM_ALIGNERS",
        "qc_variant_dedupers()",
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
    assert '--out-dir "$tmp_dir"' in extract_rule
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
    alignstats = _read("workflow/rules/alignstats.smk")
    samtools_metrics = _read("workflow/rules/samtools_metrics.smk")
    snakefile = _read("workflow/Snakefile")
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
    assert "rule=vep_chromosome" in vep
    assert "threads: config[\"vep\"][\"threads\"]" in vep
    assert 'mem_mb=config["vep"].get("mem_mb", 3000)' in vep
    assert vep.count("cluster_sample=ret_sample") >= 3
    assert "vep.input_contigs.ok" in vep
    assert "bcftools concat -a -d all" in vep
    assert "does not match input chunk count" in vep
    assert "does not match input count" in vep
    assert slurm_config["vep"]["threads"] == 8
    assert slurm_config["vep"]["mem_mb"] == 128000
    assert slurm_config["vep"]["partition"] == "i384nvme,i192nvme,i128nvme"
    assert slurm_config["vep"]["concat_threads"] == 8
    assert slurm_config["vep"]["concat_mem_mb"] == 32000
    assert slurm_config["vep"]["concat_partition"] == "i384nvme,i192nvme,i128nvme"
    assert slurm_config["vep"]["hg38_vep_chrms"] == "1-25"
    assert slurm_config["vep"]["hg38_broad_vep_chrms"] == "1-25"
    assert slurm_config["vep"]["b37_vep_chrms"] == "1-25"
    assert alignstats.count('mem_mb=config["alignstats"]["mem_mb"]') == 2
    assert slurm_config["alignstats"]["mem_mb"] == 250000
    assert slurm_config["alignstats"]["partition"] == "i384nvme,i192nvme,i128nvme"
    assert 'mem_mb=config["gen_samstats"]["mem_mb"]' in samtools_metrics
    assert slurm_config["gen_samstats"]["mem_mb"] == 64000
    assert slurm_config["gen_samstats"]["partition"] == "i192,i128"
    alignstats_compile = _read("workflow/rules/alignstats_compile.smk")
    produce_alignstats = _rule_block(alignstats_compile, "produce_alignstats")
    assert 'done=f"{MDIR}logs/produce_alignstats.done"' in produce_alignstats
    assert "shell:" in produce_alignstats
    assert "touch {output.done}" in produce_alignstats
    assert slurm_config["mosdepth"]["mem_mb"] == 64000
    assert slurm_config["mosdepth"]["partition"] == "i384nvme,i192nvme,i128nvme"
    assert slurm_config["rtg_vcfeval"]["mem_mb"] == 64000
    assert slurm_config["rtg_vcfeval"]["parse_mem_mb"] == 16000
    assert "vep_annotation_mqc.tsv" in vep
    assert "summary_glob" in vep
    assert "valid_snv_alnr_ddup_tuples(" in vep
    assert '# include: "rules/snpeff.smk"' in snakefile
    assert 'include: "rules/snpeff.smk"' not in [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]


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
        "site_mix_contam",
        "site_mix_donor",
        "contam_identity",
        "haplocheck_mtdna",
        "read_haps",
        "relatedness",
        "bcftools_variant_stats",
        "rtg_vcfstats",
        "tiddit_sv",
        "peddy_sample_qc",
        "vep_annotation",
        "htd_calls",
        "smn12_orthogonal_calls",
        "expansionhunter",
    ):
        assert key in config["custom_data"]
        assert key in config["sp"]
        assert "parent_id" in config["custom_data"][key]
        assert "parent_name" in config["custom_data"][key]

    assert "snpeff_annotation" not in config["custom_data"]
    assert "snpeff_annotation" not in config["sp"]
    assert "charr" not in config["custom_data"]
    assert "charr" not in config["sp"]
    assert config["exclude_modules"] == []
    exclude_file = REPO_ROOT / "config/multiqc_module_exclude.txt"
    assert exclude_file.exists()
    assert [
        line.strip()
        for line in exclude_file.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ] == []

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
    assert ".mosdepth.summary.txt" in trim
    assert ".mosdepth.global.dist.txt" in trim
    assert ".mosdepth.region.dist.txt" in trim
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
    assert ".peddy.sex_check.csv" in trim
    assert ".peddy.het_check.csv" in trim
    assert ".peddy.ped_check.csv" in trim
    assert ".legacy_compat.bam" in trim
    filename_modules = set(config["use_filename_as_sample_name"])
    for module in (
        "samtools",
        "picard",
        "mosdepth",
        "bcftools",
    ):
        assert module in filename_modules
    assert "verifybamid" not in filename_modules
    for module in ("goleft_indexcov", "peddy", "somalier"):
        assert module not in filename_modules
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
    assert "vep" in module_order
    assert "peddy_sample_qc" in module_order
    assert "relatedness" in module_order
    assert "verifyBAMID" not in module_order
    assert "verifybamid2_panel_comparison" not in module_order
    for module in (
        "contam_identity",
        "haplocheck_mtdna",
        "read_haps",
    ):
        assert module in module_order
    assert "charr" not in module_order


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
        assert 'module_exclude_config="config/multiqc_module_exclude.txt"' in body
        assert "multiqc_module_exclude_args.py" in body
        assert "$module_excludes" in body
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
    assert "marker = f\".{alnr}.{ddup}.{caller}.\"" in bcftools
    assert "VEP_CHRMS = [" in common
    assert "_day_chrm_token_to_contig(chrm)" in common


def test_contamination_rules_do_not_emit_per_sample_custom_content_tsvs() -> None:
    verifybamid2 = _read("workflow/rules/archived_qc/verifybamid2_contam.smk")
    gatk = _read("workflow/rules/gatk_contam.smk")
    multiqc_final = _read("workflow/rules/multiqc_final_wgs.smk")
    snakefile = _read("workflow/Snakefile")

    assert 'include: "rules/verifybamid2_contam.smk"' not in [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]
    assert "workflow/rules/archived_qc/verifybamid2_contam.smk" in snakefile
    assert "qc_contamination_dedupers()" in verifybamid2
    assert "qc_contamination_dedupers()" in gatk
    assert "vb2_mqc.tsv" not in verifybamid2.split("output:", 1)[1].split("log:", 1)[0]
    assert "gatk_mqc.tsv" not in gatk.split("output:", 1)[1].split("log:", 1)[0]
    assert "{params.old_mqc}" in verifybamid2
    assert "{params.old_mqc}" in gatk
    assert '--ignore "*vb2_mqc.tsv"' not in multiqc_final
    assert '--ignore "*gatk_mqc.tsv"' not in multiqc_final


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
        "FASTV is retired from active Snakemake execution",
        "site_mix genotype-free contamination",
        "Global contamination/identity bundle",
        "reports/multiqc_inputs/<stage>/",
        "Duplicate `(module, Sample)` pairs fail during staging",
        "`<sample>.<aligner>.<deduper>.<snv_caller>`",
        "`<sample>.<aligner>.<deduper>.<sv_caller>`",
        "Peddy CSVs and Somalier native files are rewritten",
        "`parent_id` / `parent_name` grouping",
        "QC gap:",
    ):
        assert expected in doc

    catalog = _read("docs/catalog_of_tools.md")
    assert "stage-scoped sample identity" in catalog
    assert "stage_multiqc_inputs.py" in catalog
    assert "validate_multiqc_sample_ids.py" in catalog
