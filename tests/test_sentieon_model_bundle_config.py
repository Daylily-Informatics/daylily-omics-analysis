from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
MODEL_ROOT = "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles"
PANGENOME_REF_ROOT = "/fsx/references/genomic_data/organism_references/H_sapiens/panhg38"
DNASCOPE_ONT = f"{MODEL_ROOT}/DNAscopeONT2.3.bundle"
PANGENOME_ILMN = f"{MODEL_ROOT}/SentieonIlluminaPangenomeRealignWGS1.2.bundle"
PANGENOME_ULTIMA = f"{MODEL_ROOT}/SentieonUltimaPangenomeRealignWGS1.3.bundle"
PANGENOME_HAPL = f"{PANGENOME_REF_ROOT}/hprc-v2.0-mc-grch38.hapl"
PANGENOME_GBZ = f"{PANGENOME_REF_ROOT}/hprc-v2.0-mc-grch38.gbz"
PANGENOME_ILMN_POP_VCF = f"{PANGENOME_REF_ROOT}/pop-v20-20260528.vcf.gz"
PANGENOME_ULTIMA_POP_VCF = f"{PANGENOME_REF_ROOT}/pop-v20g41-20251216.vcf.gz"


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _rule_config(profile: str) -> dict:
    path = REPO_ROOT / "config" / "day_profiles" / profile / "templates" / "rule_config.yaml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _env_text(env_yaml: str) -> str:
    return _read(f"workflow/envs/{Path(env_yaml).name}")


def _sentieon_cli_spec(env_yaml: str) -> str:
    env = yaml.safe_load(_env_text(env_yaml))
    for dep in env["dependencies"]:
        if not isinstance(dep, dict) or "pip" not in dep:
            continue
        for pip_dep in dep["pip"]:
            if "sentieon-cli" in pip_dep or "sentieon_cli" in pip_dep:
                return pip_dep
    raise AssertionError(f"No sentieon-cli dependency found in {env_yaml}")


def _assert_sentieon_cli_env(env_yaml: str, expected_cli: str) -> None:
    assert "sentieon=202503.02" in _env_text(env_yaml)
    assert _sentieon_cli_spec(env_yaml) == expected_cli


def test_sentieon_profile_templates_use_current_model_bundles() -> None:
    hiomr_cli = _sentieon_cli_spec(_rule_config("slurm")["sentdhiomr"]["env_yaml"])

    for profile in ("local", "slurm"):
        cfg = _rule_config(profile)
        text = _read(f"config/day_profiles/{profile}/templates/rule_config.yaml")

        assert "DNAscopeONT2.2.bundle" not in text
        assert "SentieonIlluminaPangenomeRealignWGS1.0.bundle" not in text
        assert "SentieonUltimaPangenomeRealignWGS1.0.bundle" not in text

        assert cfg["sentdont"]["dna_scope_snv_model"] == DNASCOPE_ONT
        assert cfg["sentdont"]["dna_scope_apply_model"] == DNASCOPE_ONT
        assert cfg["sentdont"]["pop_vcf"] == PANGENOME_ULTIMA_POP_VCF
        assert cfg["sent_aln_sort_snv"]["model"] == PANGENOME_ILMN
        assert cfg["sentieon_pangenome_sr"]["model"] == PANGENOME_ILMN
        assert cfg["sentieon_pangenome_ug"]["model"] == PANGENOME_ULTIMA
        for section in (
            "sent_aln_sort_snv",
            "sentieon_pangenome_sr",
            "sentieon_pangenome_ug",
        ):
            assert cfg[section]["hapl"] == PANGENOME_HAPL
            assert cfg[section]["gbz"] == PANGENOME_GBZ
        assert cfg["sent_aln_sort_snv"]["pop_vcf"] == PANGENOME_ILMN_POP_VCF
        assert cfg["sentieon_pangenome_sr"]["pop_vcf"] == PANGENOME_ILMN_POP_VCF
        assert cfg["sentieon_pangenome_ug"]["pop_vcf"] == PANGENOME_ULTIMA_POP_VCF
        assert "pcr_free" not in cfg["sentieon_pangenome_ug"]
        assert Path(cfg["sentdont"]["env_yaml"]).name == "sentieon_v0.3.yaml"
        assert Path(cfg["sent_aln_sort_snv"]["env_yaml"]).name == "sent_pangenome_v0.1.yaml"
        assert Path(cfg["sentieon_pangenome_sr"]["env_yaml"]).name == "sent_pangenome_v0.1.yaml"
        assert Path(cfg["sentieon_pangenome_ug"]["env_yaml"]).name == "pangenome_ultima_v0.1.yaml"
        _assert_sentieon_cli_env(cfg["sentdont"]["env_yaml"], hiomr_cli)
        _assert_sentieon_cli_env(cfg["sent_aln_sort_snv"]["env_yaml"], hiomr_cli)
        _assert_sentieon_cli_env(cfg["sentieon_pangenome_sr"]["env_yaml"], hiomr_cli)
        _assert_sentieon_cli_env(cfg["sentieon_pangenome_ug"]["env_yaml"], hiomr_cli)

    assert _rule_config("local")["sentdontr"]["dnascope_model"] == DNASCOPE_ONT
    assert _rule_config("slurm")["sentdhiomr"]["segdup_lr_model"] == DNASCOPE_ONT


def test_pangenome_rules_use_documented_sentieon_cli_shapes() -> None:
    fastq_rules = (
        _read("workflow/rules/sent_aln_sort_snv.smk"),
        _read("workflow/rules/sentieon_pangenome_shortreads.smk"),
    )

    for rule in fastq_rules:
        assert "bin/dayoa_sentieon_cli sentieon-pangenome" in rule
        assert "-r {params.huref}" in rule
        assert '--hapl "{params.hapl}"' in rule
        assert '--gbz "{params.gbz}"' in rule
        assert '-m "{params.model}"' in rule
        assert '--pop_vcf "{params.pop_vcf}"' in rule
        assert '"popvcf"' not in rule
        assert "--r1_fastq {input.f1}" in rule
        assert "--r2_fastq {input.f2}" in rule
        assert '--readgroup "@RG' in rule
        assert '-b "{params.canonical_bed}"' in rule
        assert '--dbsnp "{params.dbsnp}"' in rule
        assert 'cli_threads=min(int(config["' in rule
        assert "-t {params.cli_threads}" in rule
        assert "$pcr_flag" in rule

    ug_rule = _read("workflow/rules/sentieon_pangenome_ug.smk")
    assert "bin/dayoa_sentieon_cli sentieon-pangenome" in ug_rule
    assert "-r {params.huref}" in ug_rule
    assert '--hapl "{params.hapl}"' in ug_rule
    assert '--gbz "{params.gbz}"' in ug_rule
    assert '-m "{params.model}"' in ug_rule
    assert '--pop_vcf "{params.pop_vcf}"' in ug_rule
    assert "-i {input.cram}" in ug_rule
    assert '-b "{params.canonical_bed}"' in ug_rule
    assert '--dbsnp "{params.dbsnp}"' in ug_rule
    assert 'cli_threads=min(int(config["sentieon_pangenome_ug"]["threads"]), 128)' in ug_rule
    assert "-t {params.cli_threads}" in ug_rule
    assert 'export TMPDIR="/scratch/pangenome_ug_tmp_${{timestamp}}_$$";' in ug_rule
    assert "/fsx/scratch" not in ug_rule
    assert "/dev/shm" not in ug_rule
    assert "$pcr_flag" not in ug_rule
    assert "--pcr_free" not in ug_rule
