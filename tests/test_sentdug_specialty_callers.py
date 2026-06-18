from __future__ import annotations

import csv
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def _registry() -> list[dict[str, str]]:
    with (REPO_ROOT / "config/workflow_target_aliases.tsv").open(
        newline="", encoding="utf-8"
    ) as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def test_sentdug_specialty_rule_module_is_included_and_defines_targets() -> None:
    snakefile = _read("workflow/Snakefile")
    rules = _read("workflow/rules/sent_ug_specialty.smk")

    assert 'include: "rules/sent_ug_specialty.smk"' in snakefile
    for target in (
        "produce_sentdug_mito",
        "produce_sentdug_segdup",
        "produce_sentdug_cnv",
        "produce_sentdug_sv",
    ):
        assert f"rule {target}:" in rules
        assert f"{target}:" not in _read("workflow/rules/workflow_target_aliases.smk")


def test_sentdug_specialty_callers_consume_ug_cram_without_long_read_inputs() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")

    assert 'cram=MDIR + "{sample}/align/ug/{sample}.cram"' in rules
    assert 'crai=MDIR + "{sample}/align/ug/{sample}.cram.crai"' in rules
    assert "lr_cram" not in rules
    assert "ont_cram" not in rules
    assert "pb_cram" not in rules
    assert "--long" not in rules


def test_sentdug_segdup_consumes_cram_directly_without_specialty_bam() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")
    segdup_rule = rules.split("rule sentdug_call_segdup_gene:", 1)[1].split(
        "rule sentdug_call_segdup:", 1
    )[0]

    assert 'cram=MDIR + "{sample}/align/ug/{sample}.cram"' in segdup_rule
    assert 'crai=MDIR + "{sample}/align/ug/{sample}.cram.crai"' in segdup_rule
    assert "--short {input.cram:q}" in segdup_rule
    assert "rules.sentdug_specialty_bam" not in segdup_rule
    assert "{input.bam:q}" not in segdup_rule
    assert "{input.bai:q}" not in segdup_rule


def test_sentdug_segdup_gba_uses_supported_token_and_gba1_result_alias() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")
    segdup_rule = rules.split("rule sentdug_call_segdup_gene:", 1)[1].split(
        "rule sentdug_call_segdup:", 1
    )[0]

    assert 'return "GBA1" if gene == "GBA" else gene' in rules
    assert "--genes {wildcards.gene:q}" in segdup_rule
    assert "grep -Eq '^[[:space:]]*{params.result_gene}:'" in segdup_rule
    assert "mv {params.caller_vcf:q} {output.vcf:q}" in segdup_rule
    assert "mv {params.caller_tbi:q} {output.tbi:q}" in segdup_rule


def test_sentdug_segdup_passes_required_sample_sex() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")
    segdup_rule = rules.split("rule sentdug_call_segdup_gene:", 1)[1].split(
        "rule sentdug_call_segdup:", 1
    )[0]

    assert "sample_sex_for_required_tool(" in segdup_rule
    assert "sample_sex_assumption_log(" in segdup_rule
    assert '"Sentieon segdup"' in segdup_rule
    assert "printf '%s' {params.sex_assumption_log:q} >> {log:q}" in segdup_rule
    assert "--sex {params.sample_sex:q}" in segdup_rule


def test_sentdug_mito_and_cnv_consume_cram_directly_without_specialty_bam() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")
    cnv_rule = rules.split("rule sentdug_call_cnvs:", 1)[1].split(
        "rule sentdug_call_segdup_gene:", 1
    )[0]
    mito_rule = rules.split("rule sentdug_mito_call:", 1)[1].split(
        "align_and_call {params.mt_fasta:q}", 1
    )[0]

    for rule_text in (cnv_rule, mito_rule):
        assert 'cram=MDIR + "{sample}/align/ug/{sample}.cram"' in rule_text
        assert 'crai=MDIR + "{sample}/align/ug/{sample}.cram.crai"' in rule_text
        assert "rules.sentdug_specialty_bam" not in rule_text
        assert "{input.bam:q}" not in rule_text
        assert "{input.bai:q}" not in rule_text

    assert "-i {input.cram:q}" in cnv_rule
    assert "samtools view -T {params.huref:q}" in mito_rule
    assert "/scratch/sentdug_cnv" not in cnv_rule
    assert "/scratch/sentdug_mito" not in mito_rule
    assert "mktemp -d" in cnv_rule
    assert "mktemp -d" in mito_rule


def test_sentdug_mito_supports_unpaired_ultima_chrm_reads() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")

    assert (
        "chrM_records=$(samtools view -T {params.huref:q} -F 0x4 "
        "{input.cram:q} chrM | wc -l)"
    ) in rules
    assert "chrM same-contig paired read records" in rules
    assert "mito_read_mode=single" in rules
    assert '"$tmpdir/${{sample}}.chrM.single.fastq"' in rules
    assert '"${{read_args[@]}}"' in rules


def test_sentdug_specialty_config_keys_exist_in_profiles() -> None:
    required_keys = {
        "specialty_threads",
        "specialty_use_threads",
        "specialty_mem_mb",
        "specialty_partition",
        "cnv_model",
        "cnv_threads",
        "cnv_use_threads",
        "cnv_mem_mb",
        "segdup_sr_model",
        "segdup_population_vcf",
        "segdup_genes",
        "segdup_threads",
        "segdup_mem_mb",
        "mito_env_yaml",
        "mito_threads",
        "mito_use_threads",
        "mito_mem_mb",
        "mt_fasta",
        "mt_shifted_fasta",
        "mt_shift_back_chain",
        "mt_blacklist_bed",
        "sv_supported",
        "sv_algorithm",
        "sv_model_bundle",
        "sv_block_reason",
    }
    for profile in ("local", "slurm"):
        cfg = _yaml(f"config/day_profiles/{profile}/templates/rule_config.yaml")
        sentdug = cfg["sentdug"]
        assert required_keys <= set(sentdug), profile
        assert sentdug["sv_supported"] is False
        assert "LongReadSV" in sentdug["sv_block_reason"]
        segdup_genes = sentdug["segdup_genes"].split(",")
        assert segdup_genes == [
            "CFH",
            "CYP11B1",
            "CYP2D6",
            "GBA",
            "IKBKG",
            "NCF1",
            "PMS2",
            "RCCX",
            "SMN1",
            "STRC",
            "HBA",
        ]
        assert "GBA1" not in segdup_genes


def test_sentdug_specialty_registry_entries_are_experimental_only() -> None:
    rows = {
        row["target"]: row
        for row in _registry()
        if row["target"].startswith("produce_sentdug_")
    }

    expected = {
        "produce_sentdug_mito": "sentdug_mito",
        "produce_sentdug_segdup": "sentdug_segdup",
        "produce_sentdug_cnv": "sentdug_cnv",
        "produce_sentdug_sv": "sentdug_sv",
    }
    for target, code in expected.items():
        row = rows[target]
        assert row["kind"] == "specialty_caller"
        assert row["code"] == code
        assert row["status"] == "experimental"
        assert row["delegates_to"] == ""

    assert "sentdug_mito" not in {
        row["code"]
        for row in _registry()
        if row["kind"] in {"snv_caller", "sv_caller"} and row["status"] == "current"
    }


def test_sentdug_sv_target_is_explicitly_blocked_until_supported() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")

    assert 'raise WorkflowError(f"produce_sentdug_sv is intentionally blocked:' in rules
    assert "sv_supported" in rules
    assert "sv_algorithm" in rules
    assert "LongReadSV-based and" in rules
