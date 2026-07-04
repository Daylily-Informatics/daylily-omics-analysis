from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def test_htd_callers_default_empty_in_profiles() -> None:
    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        config = _yaml(path)
        assert config["htd_callers"] == []
        assert "enabled" not in config["hapsma"]


def test_slurm_htd_callers_use_explicit_resource_blocks() -> None:
    config = _yaml("config/day_profiles/slurm/templates/rule_config.yaml")

    assert config["gauchian"] == {
        "threads": 1,
        "mem_mb": 50000,
        "partition": "i192hugenvme,i192nvme,i384nvme",
    }
    assert config["cyrius"]["threads"] == 128
    assert config["cyrius"]["mem_mb"] == 128000
    assert config["cyrius"]["partition"] == "i192hugenvme,i192nvme,i384nvme"
    for caller in (
        "smn12",
        "smncopynumbercaller_contract_validation",
        "smaca",
        "sma_finder",
        "hapsma",
        "paraphase_ont_exploratory",
    ):
        assert config[caller]["threads"] == 192
        assert config[caller]["mem_mb"] == 250000
        assert config[caller]["partition"] == "i192hugenvme,i192nvme,i384nvme"
    assert config["hapsma"]["min_smn_region_mean_coverage"] == 4
    assert config["hapsma"]["start"] == "bam_single_remap"
    assert config["hapsma"]["ploidy"] == "4"
    assert config["hapsma"]["smn_region"] == "chr5:69949533-71054170"
    assert config["hapsma"]["calling_target_region"] == "chr5:70049522-70954173"
    assert config["hapsma"]["phaseset_region"] == "chr5:69949533-71054170"
    assert config["hapsma"]["calling_target_bed"]["hg38"].endswith(
        "/runtime_assets/tool_specific_resources/hapsma/hg38/SMN_region_38.smn_only.bed"
    )
    assert config["hapsma"]["homopolymer_bed"]["hg38"].endswith(
        "/runtime_assets/tool_specific_resources/hapsma/hg38/hg38_smn_100kb_pad_homopolymer_run3.bed"
    )
    assert config["hapsma"]["clair3model"].endswith(
        "/runtime_assets/tool_specific_resources/clair3/models/r1041_e82_400bps_sup_v500"
    )
    assert config["hapsma"]["minimap_index"]["hg38"].endswith(
        "/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta"
    )
    for key in (
        "calling_target_bed",
        "calling_target_region",
        "phaseset_region",
        "homopolymer_bed",
        "clair3model",
        "minimap_index",
    ):
        assert key in config["hapsma"]
    assert config["sentdhiomr"]["segdup_threads"] == 48
    assert config["sentdhiomr"]["segdup_mem_mb"] == 48000
    assert config["sentdhiomr"]["segdup_lr_model"].endswith("/DNAscopeONT2.3.bundle")


def test_common_declares_supported_htd_callers_and_validation() -> None:
    common = _read("workflow/rules/common.smk")

    for caller in (
        "gauchian",
        "cyrius",
        "smn12",
        "parascopy",
        "smaca",
        "sma_finder",
        "hapsma",
    ):
        assert f'"{caller}"' in common
    assert '"genetocn"' not in common[
        common.index("SUPPORTED_HTD_CALLERS") : common.index("def _supporting_file_name")
    ]
    assert "SUPPORTED_HTD_CALLERS" in common
    assert "def htd_callers_selected" in common
    assert "Unsupported htd_callers value" in common
    assert "produce_htd_calls requires a non-empty" in common


def test_active_and_disabled_htd_rule_includes_are_explicit() -> None:
    snakefile = _read("workflow/Snakefile")
    active_includes = [
        line.strip()
        for line in snakefile.splitlines()
        if line.strip().startswith("include:")
    ]

    assert 'include: "rules/cyp2d6_cyrius.smk"' in snakefile
    assert 'include: "rules/htd_calls.smk"' in snakefile
    assert 'include: "rules/gauchian.smk"' in active_includes
    assert "Historical alternate GBA integration" in snakefile
    assert 'include: "rules/parascopy.smk"' in active_includes
    assert 'include: "rules/smaca.smk"' in active_includes
    assert 'include: "rules/sma_finder.smk"' in active_includes
    assert 'include: "rules/hapsma.smk"' in active_includes
    assert 'include: "rules/smn12_input_qc.smk"' in active_includes
    assert 'include: "rules/smn12_orthogonal_calls.smk"' in active_includes
    assert 'include: "rules/smn_copynumbercaller.smk"' in active_includes
    assert 'include: "rules/smncopynumbercaller_contract_validation.smk"' in active_includes
    assert 'include: "rules/paraphase_ont_exploratory.smk"' in active_includes
    assert "strict short-read" in snakefile
    assert 'include: "rules/genetocn.smk"' not in active_includes
    assert '# include: "rules/genetocn.smk"' in snakefile
    assert "GeneToCN is disabled until its upstream package/install surface" in snakefile
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
    assert 'threads: config["cyrius"]["threads"]' in cyrius
    assert 'mem_mb=config["cyrius"]["mem_mb"]' in cyrius


def test_gauchian_rule_is_active_and_single_thread_explicit() -> None:
    gauchian = _read("workflow/rules/gauchian.smk")

    for expected in (
        "rule gauchian:",
        "rule produce_gauchian:",
        "htd/gauchian",
        ".gauchian.done",
        '"../envs/gba_v0.1.yaml"',
        'threads: config["gauchian"]["threads"]',
        'mem_mb=config["gauchian"]["mem_mb"]',
        "gauchian \\",
        "-m {output.manifest}",
        "--reference {params.huref}",
        "-g {params.genome}",
        "-o \"${{out_dir}}\"",
        "-p {params.prefix}",
    ):
        assert expected in gauchian
    assert "--threads" not in gauchian


def test_gauchian_env_uses_installable_upstream_dependencies() -> None:
    env = _read("workflow/envs/gba_v0.1.yaml")

    assert "git+https://github.com/Illumina/Gauchian.git@e69ceee9ed88ec58c45fd27b899d83e91bbb1afb" in env
    for dependency in (
        "samtools",
        "numpy",
        "pysam",
        "scipy",
        "statsmodels",
        "pytest-runner",
        "python-dateutil",
    ):
        assert dependency in env
    assert "--no-deps" not in env
    assert "str_analysis" not in env


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
        "smn12.done",
        "htd_smn12_preflight_needed",
        "smn12_preflight_mqc.tsv",
        "smaca.summary.tsv",
        "smaca.done",
        "sma_finder.summary.tsv",
        "sma_finder.summary.json",
        "sma_finder.done",
        "hapsma.summary.tsv",
        "hapsma.done",
        "htd/parascopy",
        "parascopy.done",
        "smn_short_read_alnr_ddup_pairs()",
        "smn_long_read_alnr_ddup_pairs()",
        "expand_smn_alnr_ddup_pairs(",
    ):
        assert expected in htd
    assert "genetocn.done" not in htd


def test_htd_mqc_script_schema_and_smn_capability_fields() -> None:
    script = _read("workflow/scripts/htd_calls_mqc.py")

    for expected in (
        "HTD_RE",
        "CYP2D6",
        "Genotype",
        "Filter",
        "caller_class",
        "evidence_source",
        "smn1_copy_number",
        "smn2_copy_number",
        "affected_status",
        "carrier_status",
        "long_read_haplotype_dev",
        "affected_status_only",
        "not_reported",
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
    sma_finder = _read("workflow/rules/sma_finder.smk")
    hapsma = _read("workflow/rules/hapsma.smk")
    genetocn = _read("workflow/rules/genetocn.smk")
    htd_calls = _read("workflow/rules/htd_calls.smk")
    smn12_qc = _read("workflow/rules/smn12_input_qc.smk")

    for text in (gauchian, parascopy, genetocn):
        assert "QC_CRAM_ALIGNERS" in text
    for text in (smn12, smaca, sma_finder):
        assert "smn_short_cram" in text
        assert "smn_short_crai" in text
        assert "preflight=smn12_input_qc_done" in text
        assert "smn_short_read_alnr_ddup_pairs()" in text
        assert "expand_smn_alnr_ddup_pairs(" in text
    assert "rule smn12_input_qc:" in smn12_qc
    assert "whole-genome BAM/CRAM" in smn12_qc
    assert "smn_long_cram" in hapsma
    assert "smn_long_crai" in hapsma
    assert "smn_long_read_alnr_ddup_pairs()" in hapsma
    assert "expand_smn_alnr_ddup_pairs(" in hapsma
    assert "def genetocn_cram" in genetocn
    assert "def genetocn_inputs" not in genetocn
    assert "cram=genetocn_cram" in genetocn
    assert "htd/gauchian" in htd_calls
    assert "gauchian.done" in htd_calls
    assert "{sample}/align/{alnr}/{ddup}/htd/parascopy/{sample}.{alnr}.{ddup}.parascopy.done" in parascopy
    assert "threads: _parascopy_threads()" in parascopy
    assert "--threads {threads}" in parascopy
    assert "htd/parascopy" in htd_calls
    assert "parascopy.done" in htd_calls
    assert "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done" in smaca
    assert "htd/smaca" in htd_calls
    assert "smaca.done" in htd_calls
    assert "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.done" in sma_finder
    assert "htd/sma_finder" in htd_calls
    assert "sma_finder.done" in htd_calls
    assert "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done" in hapsma
    assert "htd/hapsma" in htd_calls
    assert "hapsma.done" in htd_calls
    assert "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.summary.json" in smn12
    assert "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.done" in smn12
    assert "htd/smn12" in htd_calls
    assert "smn12.summary.json" in htd_calls
    assert "{sample}/align/{alnr}/{ddup}/htd/genetocn/{sample}.{alnr}.{ddup}.genetocn.done" in genetocn
    assert "htd/genetocn" not in htd_calls
    assert "genetocn.done" not in htd_calls


def test_smn12_uses_hybrid_sr_cram_and_hard_validates_summary() -> None:
    common = _read("workflow/rules/common.smk")
    smn12 = _read("workflow/rules/smn_copynumbercaller.smk")

    for expected in (
        "def smn_short_cram",
        "_smn_hiomr_aligners()",
        "sentdhiomr.sr_dedup.cram",
        "SMN short-read callers must not consume long-read-only or graph-only",
        'SMN_SHORT_READ_NA_DEDUP_ALIGNERS = {"bwa2a", "sent", "strobe"}',
        'ddup != "na" or alnr in SMN_SHORT_READ_NA_DEDUP_ALIGNERS',
        "def smn_long_cram",
        "_sentdhiomr_lr_cram(wildcards)",
        "SMN long-read callers require ONT evidence",
    ):
        assert expected in common
    for expected in (
        "def smn12_cram",
        "return smn_short_cram(wildcards)",
        "return smn_short_crai(wildcards)",
        "preflight=smn12_input_qc_done",
        "done=MDIR",
        "rm -f {output.summary} {output.done}",
        "smn_caller.py",
        'data_dir="workflow/resources/smn12"',
        "test -s {params.data_dir}/SMN_region_{params.genome}.bed",
        "test -s {params.data_dir}/SMN_gmm.txt",
        "smn_workdir=$(mktemp -d)",
        'ln -s "$PWD/{params.data_dir}" "$smn_workdir/data"',
        '"$CONDA_PREFIX/bin/python" "$smn_workdir/smn_caller.py"',
        "--manifest \"$manifest\"",
        "--genome {params.genome}",
        "--prefix {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.smn12.summary",
        "test -s {output.summary}",
        '"$CONDA_PREFIX/bin/python" -m json.tool {output.summary} >/dev/null',
        "touch {output.done}",
        '"../envs/smn12_v0.1.yaml"',
    ):
        assert expected in smn12
    assert "SMNCopyNumberCaller \\" not in smn12
    assert 'echo "{}" > {output.summary}' not in smn12


def test_smaca_sma_finder_and_hapsma_runtime_contracts() -> None:
    smaca = _read("workflow/rules/smaca.smk")
    sma_finder = _read("workflow/rules/sma_finder.smk")
    hapsma = _read("workflow/rules/hapsma.smk")

    for expected in (
        "rule smaca:",
        "cram=smn_short_cram",
        "crai=smn_short_crai",
        "preflight=smn12_input_qc_done",
        "--reference",
        "--ncpus",
        "SMAca command was not found on PATH",
        "SMAca summary has no header",
        'Running command: %s\\\\n',
        '"../envs/smaca_v0.1.yaml"',
    ):
        assert expected in smaca
    for expected in (
        "rule sma_finder:",
        "cram=smn_short_cram",
        "crai=smn_short_crai",
        "preflight=smn12_input_qc_done",
        "--hg38-reference-fasta",
        "affected_status_only",
        "sma-finder command was not found on PATH",
        'Running command: %s\\\\n',
        '"../envs/sma_finder_v0.1.yaml"',
    ):
        assert expected in sma_finder
    for expected in (
        "rule hapsma:",
        "cram=smn_long_cram",
        "crai=smn_long_crai",
        "HapSMA is dev_exploratory",
        "requires config.hapsma.",
        "_hapsma_value",
        "genome_build",
        "for genome_build={genome_build}.",
        "samtools depth -r",
        "no_call_low_coverage",
        "HapSMA no-call low coverage",
        "bam_single_remap",
        "sambamba view",
        "minimap2 -t",
        "params.minimap_index",
        "CONDA_PREFIX",
        "gatk --java-options",
        "whatshap polyphase",
        "whatshap haplotag",
        'vc.hasAttribute("RegionRef")',
        "whatshap_status=$?",
        "whatshap_exit=$whatshap_status",
        "whatshap haplotag failed for phased HapSMA",
        "run_clair3.sh",
        "sniffles",
        "No HapSMA PhaseSet was detected",
        "not found in index",
        "no_call_no_phase_set",
        "no_call_no_dominant_phase_set",
        "phaseset.status.tsv",
        "bed_phase_status",
        "bed_phase_reason",
        "region_phase_status",
        "region_phase_reason",
        'f"{{status}}\\t{{phase_set}}\\t{{reason}}\\n"',
        'f"Missing HapSMA phase status file: {{path}}"',
        "NR == 2 {{print $1}}",
        "NR == 2 {{print $3}}",
        "long_read_haplotype",
        "dev_exploratory",
        '"../envs/hapsma_v0.1.yaml"',
    ):
        assert expected in hapsma
    assert "nextflow" not in hapsma
    assert "hapsma.enabled" not in hapsma


def test_smn12_resource_bundle_contains_required_files() -> None:
    data_dir = REPO_ROOT / "workflow" / "resources" / "smn12"

    for genome in ("19", "37", "38"):
        assert (data_dir / f"SMN_region_{genome}.bed").is_file()
        assert (data_dir / f"SMN_SNP_{genome}.txt").is_file()
        assert (data_dir / f"SMN_target_variant_{genome}.txt").is_file()
    assert (data_dir / "SMN_gmm.txt").is_file()


def test_smncopy_contract_target_is_manifest_driven_whole_genome_only() -> None:
    rule = _read("workflow/rules/smncopynumbercaller_contract_validation.smk")
    script = _read("workflow/scripts/smncopynumbercaller_contract_summary.py")

    for expected in (
        "rule smncopynumbercaller_contract_validation:",
        "rule produce_smncopynumbercaller_contract_validation:",
        "smncopynumbercaller_contract_manifest",
        "SMNCOPY_CONTRACT_REQUIRED_COLUMNS",
        "input_cram_or_bam",
        "input_index",
        "reference_fasta",
        "resource_dir",
        "source_analysis",
        "whole_genome_wgs_bam_cram",
        "workflow/scripts/smn12_input_qc.py",
        "--aligner smncopy_contract",
        "--deduper whole_genome_input",
        "SMN12 input preflight failed required checks",
        "smn_caller.py",
        "--manifest \"$manifest\"",
        "smncopy_contract_results.tsv",
        '"../envs/smn12_v0.1.yaml"',
    ):
        assert expected in rule
    for expected in (
        "FIELDNAMES",
        "PARSE_INCOMPLETE",
        "SMNCopyNumberCaller",
        "whole_genome_wgs_bam_cram",
        "preflight_failed_requirements",
        "NO_EXACT_CN",
        "DISCORDANT",
        "MATCH",
    ):
        assert expected in script


def test_paraphase_ont_target_is_exploratory_and_not_production_htd() -> None:
    rule = _read("workflow/rules/paraphase_ont_exploratory.smk")
    script = _read("workflow/scripts/paraphase_ont_exploratory_summary.py")
    env = _read("workflow/envs/paraphase_v3.5.yaml")
    htd = _read("workflow/rules/htd_calls.smk")

    for expected in (
        "rule paraphase_ont_exploratory:",
        "rule produce_paraphase_ont_exploratory:",
        "paraphase_ont_manifest",
        "PARAPHASE_ONT_REQUIRED_COLUMNS",
        "ont_input_cram_or_bam",
        "EXPLORATORY_ONT_PARAPHASE",
        "ONT_CRAM_CONVERTED_TO_BAM_FOR_PARAPHASE",
        "paraphase \\",
        "-g smn1",
        "--genome 38",
        "paraphase_ont_results.tsv",
        '"../envs/paraphase_v3.5.yaml"',
    ):
        assert expected in rule
    for expected in (
        "EXPLORATORY_ONT_PARAPHASE",
        "PARSED_EXACT_CN_EXPLORATORY",
        "DISCORDANT_EXPLORATORY",
        "MATCH_EXPLORATORY",
    ):
        assert expected in script
    assert "paraphase==3.5.0" in env
    assert "samtools>=1.23" in env
    assert "paraphase_ont_exploratory" not in htd


def test_smn12_input_qc_contract_is_strict_and_multiqc_ready() -> None:
    rule = _read("workflow/rules/smn12_input_qc.smk")
    script = _read("workflow/scripts/smn12_input_qc.py")
    config = _yaml("config/day_profiles/slurm/templates/rule_config.yaml")

    for expected in (
        "rule smn12_input_qc:",
        "rule smn12_input_qc_mqc:",
        "rule produce_smn12_input_qc:",
        "SMN_region_{params.genome}.bed",
        "SMN_SNP_{params.genome}.txt",
        "SMN_target_variant_{params.genome}.txt",
        "smn12_input_qc.tsv",
        "smn12_region_depth.tsv",
        "smn12_required_regions_status.tsv",
        "smn12_alignment_flags.tsv",
        "smn12_preflight_mqc.tsv",
        '"../envs/smn12_v0.1.yaml"',
    ):
        assert expected in rule

    for expected in (
        "FIELDNAMES_INPUT_QC",
        "FIELDNAMES_REGION_DEPTH",
        "FIELDNAMES_FLAGS",
        "FIELDNAMES_REQUIRED",
        "FIELDNAMES_MQC",
        "whole_genome_wgs_bam_cram",
        "diagnostic_bamlet_or_cramlet",
        "SMN12 input preflight failed required checks",
        "production_eligible",
        "exon16",
        "exon78",
        "normalization_bins",
        "selected_snp_sites",
        "target_variant_sites",
        "pct_secondary",
        "pct_supplementary",
        "pct_clipped",
    ):
        assert expected in script
    assert config["smn12_input_qc"]["threads"] == 8
    assert config["smn12_input_qc"]["mem_mb"] == 50000
    assert config["smn12_input_qc"]["min_norm_bin_present_fraction"] == 0.95


def test_final_multiqc_and_multiqc_config_include_htd_when_selected() -> None:
    final = _read("workflow/rules/multiqc_final_wgs.smk")
    multiqc = _yaml("config/external_tools/multiqc_config.yaml")

    assert "if HTD_CALLERS:" in final
    assert "htd_calls_mqc.tsv" in final
    assert "produce_smn12_input_qc" in final
    assert "smn12_preflight_mqc.tsv" in final
    assert "produce_smn12_orthogonal_calls" in final
    assert "smn12_orthogonal_calls_mqc.tsv" in final
    assert "htd_calls" in multiqc["custom_data"]
    assert multiqc["sp"]["htd_calls"]["fn"] == "other_reports/htd_calls_mqc.tsv"
    assert "smn12_preflight" in multiqc["custom_data"]
    assert multiqc["sp"]["smn12_preflight"]["fn"] == "other_reports/smn12_preflight_mqc.tsv"
    assert "smn12_orthogonal_calls" in multiqc["custom_data"]
    assert (
        multiqc["sp"]["smn12_orthogonal_calls"]["fn"]
        == "other_reports/smn12_orthogonal_calls_mqc.tsv"
    )


def test_smn12_orthogonal_target_includes_caller_evidence_sources() -> None:
    rule = _read("workflow/rules/smn12_orthogonal_calls.smk")
    script = _read("workflow/scripts/smn12_orthogonal_calls_mqc.py")

    for expected in (
        "rule produce_smn12_orthogonal_calls:",
        "preflight=smn12_input_qc_outputs",
        "smn12_preflight_mqc.tsv",
        "smn12.summary.json",
        "smaca.summary.tsv",
        "sma_finder.summary.tsv",
        "hapsma.summary.tsv",
        "sentdhiomr.segdup.SMN1.done",
        "requires Sentieon HiOMR segdup_genes",
        "other_reports/smn12_orthogonal_calls_mqc.tsv",
    ):
        assert expected in rule
    assert "hapsma.enabled" not in rule
    for expected in (
        "sentieon_segdup_smn1",
        "hybrid_segdup",
        "_smaca_row",
        "_extract_copy_number",
        "discordance_flag",
        "no_discordance_detected",
        "affected_status_only",
        "long_read_haplotype_dev",
    ):
        assert expected in script


def test_htd_mqc_extracts_smaca_copy_numbers(tmp_path: Path) -> None:
    summary = (
        tmp_path
        / "S1/align/sent/dmd/htd/smaca/S1.sent.dmd.smaca.summary.tsv"
    )
    done = tmp_path / "S1/align/sent/dmd/htd/smaca/S1.sent.dmd.smaca.done"
    output = tmp_path / "other_reports/htd_calls_mqc.tsv"
    summary.parent.mkdir(parents=True)
    summary.write_text(
        "sample\tSMN1_copy_number\tSMN2_copy_number\nS1\t2\t1\n",
        encoding="utf-8",
    )
    done.write_text("", encoding="utf-8")

    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow/scripts/htd_calls_mqc.py"),
            "--output",
            str(output),
            str(summary),
            str(done),
        ],
        check=True,
    )

    rows = _read_tsv(output)
    assert rows[0]["caller"] == "smaca"
    assert rows[0]["smn1_copy_number"] == "2"
    assert rows[0]["smn2_copy_number"] == "1"
    assert rows[0]["status"] == "complete"


def test_smn12_orthogonal_mqc_extracts_smaca_copy_numbers_from_gene_rows(
    tmp_path: Path,
) -> None:
    summary = (
        tmp_path
        / "S1/align/sent/dmd/htd/smaca/S1.sent.dmd.smaca.summary.tsv"
    )
    done = tmp_path / "S1/align/sent/dmd/htd/smaca/S1.sent.dmd.smaca.done"
    output = tmp_path / "other_reports/smn12_orthogonal_calls_mqc.tsv"
    summary.parent.mkdir(parents=True)
    summary.write_text(
        "gene\tcopy_number\nSMN1\t2\nSMN2\t1\n",
        encoding="utf-8",
    )
    done.write_text("", encoding="utf-8")

    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow/scripts/smn12_orthogonal_calls_mqc.py"),
            "--output",
            str(output),
            str(summary),
            str(done),
        ],
        check=True,
    )

    rows = _read_tsv(output)
    assert rows[0]["caller"] == "smaca"
    assert rows[0]["smn1_copy_number"] == "2"
    assert rows[0]["smn2_copy_number"] == "1"
    assert rows[0]["discordance_flag"] == "no_discordance_detected"
