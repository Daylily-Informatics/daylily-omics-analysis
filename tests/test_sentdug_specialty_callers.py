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


def test_sentdug_mito_supports_unpaired_ultima_chrm_reads() -> None:
    rules = _read("workflow/rules/sent_ug_specialty.smk")

    assert 'chrM_records=$(samtools view -F 0x4 {input.bam:q} chrM | wc -l)' in rules
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
