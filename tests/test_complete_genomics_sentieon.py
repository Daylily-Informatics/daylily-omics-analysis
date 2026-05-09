from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_rule_config(profile: str) -> dict:
    path = REPO_ROOT / "config" / "day_profiles" / profile / "templates" / "rule_config.yaml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_cgt7p_uses_mgi_model_member_paths_in_both_profiles() -> None:
    expected_dnascope_model = (
        "/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/"
        "DNAscopeMGIWGS2.1.bundle/dnascope.model"
    )
    expected_bwa_model = (
        "/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/"
        "DNAscopeMGIWGS2.1.bundle/bwa.model"
    )

    for profile in ("local", "slurm"):
        cfg = _load_rule_config(profile)
        assert cfg["cgt7p"]["dna_scope_snv_model"] == expected_dnascope_model
        assert cfg["sentieon_cgt7p"]["bwa_model"] == expected_bwa_model
        assert cfg["sentieon_cgt7p"]["read_group_platform"] == "DNBSEQ"


def test_complete_genomics_cli_and_rule_maps_point_cgt7p_to_sentcg() -> None:
    common_smk = (REPO_ROOT / "workflow" / "rules" / "common.smk").read_text(encoding="utf-8")
    day_run = (REPO_ROOT / "bin" / "day_run").read_text(encoding="utf-8")

    assert '"produce_sentieon_cgt7p_bwa_sort_bam": "sentcg"' in common_smk
    assert '"produce_cgt7p_vcf": "sentcg"' in common_smk
    assert '"cgt7p":    ["sentcg"]' in common_smk

    assert 'produce_sentieon_cgt7p_bwa_sort_bam) _aligner_codes+=("sentcg")' in day_run
    assert 'produce_cgt7p_vcf)              _aligner_codes+=("sentcg")' in day_run


def test_doppelmark_disables_optical_duplicate_parsing_for_sentcg() -> None:
    rule_text = (REPO_ROOT / "workflow" / "rules" / "doppel_mrkdups.smk").read_text(
        encoding="utf-8"
    )

    assert "def _doppelmark_optical_distance(wildcards):" in rule_text
    assert 'wildcards.alnr == "sentcg"' in rule_text
    assert "return -1" in rule_text
    assert "-optical-distance {params.optical_distance}" in rule_text
