from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SLURM_RULE_CONFIG = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
LOCAL_RULE_CONFIG = REPO_ROOT / "config/day_profiles/local/templates/rule_config.yaml"
SENTDHIOMR_RULES = REPO_ROOT / "workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk"


EXPECTED_SLURM_TUNING = {
    "threads_snv": 48,
    "use_threads_snv": 46,
    "mem_mb_snv": 128000,
    "threads_snv_medium": 32,
    "use_threads_snv_medium": 30,
    "mem_mb_snv_medium": 64000,
    "threads_snv_light": 4,
    "use_threads_snv_light": 3,
    "mem_mb_snv_light": 50000,
    "time_snv_stage3": 720,
    "time_snv_transfer": 720,
    "time_snv_transfer_merge": 720,
    "transfer_partition": "i192,i128",
    "sr_markdup_threads": 64,
    "sr_markdup_mem_mb": 64000,
    "segdup_threads": 48,
    "segdup_mem_mb": 48000,
}


def _load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_slurm_sentdhiomr_conservative_tuning_values() -> None:
    sentdhiomr = _load_yaml(SLURM_RULE_CONFIG)["sentdhiomr"]

    for key, expected in EXPECTED_SLURM_TUNING.items():
        assert sentdhiomr[key] == expected

    assert sentdhiomr["threads"] == 96
    assert sentdhiomr["mem_mb"] == 300000
    assert sentdhiomr["sr_align_tmp_parent"] == "/scratch"
    assert sentdhiomr["stage3_tmp_parent"] == "/fsx/scratch"
    assert sentdhiomr["transfer_tmp_parent"] == "/fsx/scratch"


def test_local_sentdhiomr_declares_tuning_keys_for_parseability() -> None:
    sentdhiomr = _load_yaml(LOCAL_RULE_CONFIG)["sentdhiomr"]

    missing = sorted(set(EXPECTED_SLURM_TUNING) - set(sentdhiomr))
    assert not missing
    assert sentdhiomr["sr_align_tmp_parent"] == "/tmp"
    assert sentdhiomr["stage3_tmp_parent"] == "/tmp"
    assert sentdhiomr["transfer_tmp_parent"] == "/tmp"


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
    assert "sample_sex_for_required_tool(" in segdup_block
    assert "sample_sex_assumption_log(" in segdup_block
    assert "--sex {params.sample_sex:q}" in segdup_block


def test_sentdhiomr_stage3_uses_configured_tmp_parent() -> None:
    text = SENTDHIOMR_RULES.read_text(encoding="utf-8")
    stage3 = text.split("rule sentdhiomr_stage3:", 1)[1].split(
        "rule sentdhiomr_pass2:", 1
    )[0]

    assert 'tmp_parent=config["sentdhiomr"]["stage3_tmp_parent"]' in stage3
    assert "time=config['sentdhiomr'].get('time_snv_stage3', 720)" in stage3
    assert 'tmp_parent="{params.tmp_parent}"' in stage3
    assert 'test -w "$tmp_parent"' in stage3
    assert 'sentdhiomr_s3_${{timestamp}}_$$' in stage3


def test_sentdhiomr_sr_align_uses_configured_tmp_parent() -> None:
    text = SENTDHIOMR_RULES.read_text(encoding="utf-8")
    sr_align = text.split("rule sentdhiomr_sr_align:", 1)[1].split(
        "rule sentdhiomr_pass1:", 1
    )[0]

    assert 'tmp_parent=config["sentdhiomr"]["sr_align_tmp_parent"]' in sr_align
    assert 'tmp_parent="{params.tmp_parent}"' in sr_align
    assert 'test -w "$tmp_parent"' in sr_align
    assert 'sentdhiomr_sr_${{timestamp}}_$$' in sr_align
    assert 'export TMPDIR="/tmp/sentdhiomr_sr_' not in sr_align


def test_sentdhiomr_transfer_uses_configured_tmp_parent() -> None:
    text = SENTDHIOMR_RULES.read_text(encoding="utf-8")
    transfer = text.split("rule sentdhiomr_transfer:", 1)[1].split(
        "rule sentdhiomr_transfer_merge:", 1
    )[0]

    assert 'tmp_parent=config["sentdhiomr"]["transfer_tmp_parent"]' in transfer
    assert (
        "partition=config['sentdhiomr'].get('transfer_partition', 'i192,i128')"
        in transfer
    )
    assert 'tmp_parent="{params.tmp_parent}"' in transfer
    assert 'test -w "$tmp_parent"' in transfer
    assert 'sentdhiomr_transfer_{wildcards.dchrm}_{wildcards.tchrm}_${{timestamp}}_$$' in transfer
    assert "TMPDIR=$(dirname {output.vcf})" not in transfer


def test_sentdhiomr_transfer_merge_uses_configured_tmp_parent() -> None:
    text = SENTDHIOMR_RULES.read_text(encoding="utf-8")
    transfer_merge = text.split("rule sentdhiomr_transfer_merge:", 1)[1].split(
        "rule sentdhiomr_model_apply:", 1
    )[0]

    assert 'tmp_parent=config["sentdhiomr"]["transfer_tmp_parent"]' in transfer_merge
    assert (
        "partition=config['sentdhiomr'].get('transfer_partition', 'i192,i128')"
        in transfer_merge
    )
    assert 'tmp_parent="{params.tmp_parent}"' in transfer_merge
    assert 'test -w "$tmp_parent"' in transfer_merge
    assert 'sentdhiomr_transfer_merge_{wildcards.dchrm}_${{timestamp}}_$$' in transfer_merge
    assert 'bcftools concat --threads {threads} -a -d all -O z -o "$tmp_vcf"' in transfer_merge
    assert "cp \"$tmp_vcf\" {output.vcf}" in transfer_merge
