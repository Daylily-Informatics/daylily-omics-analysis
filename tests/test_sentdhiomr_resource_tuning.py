from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SLURM_RULE_CONFIG = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
LOCAL_RULE_CONFIG = REPO_ROOT / "config/day_profiles/local/templates/rule_config.yaml"
SENTDHIOMR_RULES = REPO_ROOT / "workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk"


EXPECTED_SLURM_TUNING = {
    "threads_snv": 96,
    "use_threads_snv": 94,
    "mem_mb_snv": 128000,
    "threads_snv_medium": 32,
    "use_threads_snv_medium": 30,
    "mem_mb_snv_medium": 64000,
    "threads_snv_light": 4,
    "use_threads_snv_light": 3,
    "mem_mb_snv_light": 8000,
    "sr_markdup_threads": 64,
    "sr_markdup_mem_mb": 64000,
    "segdup_threads": 192,
    "segdup_mem_mb": 300000,
}


def _load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_slurm_sentdhiomr_conservative_tuning_values() -> None:
    sentdhiomr = _load_yaml(SLURM_RULE_CONFIG)["sentdhiomr"]

    for key, expected in EXPECTED_SLURM_TUNING.items():
        assert sentdhiomr[key] == expected

    assert sentdhiomr["threads"] == 192
    assert sentdhiomr["mem_mb"] == 300000


def test_local_sentdhiomr_declares_tuning_keys_for_parseability() -> None:
    sentdhiomr = _load_yaml(LOCAL_RULE_CONFIG)["sentdhiomr"]

    missing = sorted(set(EXPECTED_SLURM_TUNING) - set(sentdhiomr))
    assert not missing


def test_sentdhiomr_rules_use_tuned_resources_without_tuning_sr_align_or_sv() -> None:
    text = SENTDHIOMR_RULES.read_text(encoding="utf-8")

    assert "rule sentdhiomr_sr_align:" in text
    sr_align = text.split("rule sentdhiomr_sr_align:", 1)[1].split(
        "rule sentdhiomr_pass1:", 1
    )[0]
    assert "threads: config['sentdhiomr']['threads']" in sr_align
    assert "mem_mb=config['sentdhiomr']['mem_mb']" in sr_align

    snv_block = text.split("rule sentdhiomr_pass1:", 1)[1].split(
        "rule sentdhiomr_call_svs:", 1
    )[0]
    assert snv_block.count("threads: config['sentdhiomr']['threads_snv']") >= 4
    assert snv_block.count("mem_mb=config['sentdhiomr']['mem_mb_snv']") >= 4
    assert "threads: config['sentdhiomr']['sr_markdup_threads']" in snv_block
    assert "mem_mb=config['sentdhiomr']['sr_markdup_mem_mb']" in snv_block
    assert "threads: config['sentdhiomr']['threads_snv_medium']" in snv_block
    assert "threads: config['sentdhiomr']['threads_snv_light']" in snv_block

    sv_block = text.split("rule sentdhiomr_call_svs:", 1)[1].split(
        "rule sentdhiomr_call_cnvs:", 1
    )[0]
    assert "threads: config['sentdhiomr']['threads']" in sv_block
    assert "mem_mb=config['sentdhiomr']['mem_mb']" in sv_block

    segdup_block = text.split("rule sentdhiomr_call_segdup_gene:", 1)[1].split(
        "rule sentdhiomr_call_segdup:", 1
    )[0]
    assert "threads: config['sentdhiomr']['segdup_threads']" in segdup_block
    assert "mem_mb=config['sentdhiomr']['segdup_mem_mb']" in segdup_block
