from __future__ import annotations

import re
import shlex
from pathlib import Path
from types import SimpleNamespace

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SLURM_RULE_CONFIG = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
ACTIVE_RULES_DIR = REPO_ROOT / "workflow/rules"
V8_PARTITIONS = {
    "i8",
    "i128",
    "i192",
    "i128nvme",
    "i192nvme",
    "i384nvme",
    "i192hugenvme",
}
RETIRED_PARTITIONS = {
    "i192mem",
    "i192bigmem",
    "bcl-convert",
    "bcl2fq-i192-nvme-test",
    "bcl2fq-i384-nvme-test",
}
ALIGN_DEDUP_CONFIG_SECTIONS = {
    "bwa_mem2a_aln_sort",
    "sentmm2_align_sort",
    "sentmm2ont_align_sort",
    "strobe_align_sort",
    "doppelmark",
    "sent_dedup",
}
ALIGN_DEDUP_RULE_FILES = {
    "bwa_mem2a_align_sort.smk",
    "sentmm2_align_sort.smk",
    "sentmm2ont_align_sort.smk",
    "strobe_align_sort.smk",
    "sent_aln_sort_snv.smk",
    "sentieon_markdups.smk",
    "doppel_mrkdups.smk",
    "sentieon_pangenome_shortreads.smk",
    "sent_hybrid_ilmn_ont_modular.refactored.smk",
    "sent_hybrid_ilmn_pb_modular.refactored.smk",
    "sent_hybrid_ug_ont_modular.refactored.smk",
    "sent_hybrid_ug_pb_modular.refactored.smk",
}
PANGENOME_SLURM_RESOURCE_SECTIONS = {
    "sent_aln_sort_snv": "sent_aln_sort_snv.smk",
    "sentieon_pangenome_sr": "sentieon_pangenome_shortreads.smk",
    "sentieon_pangenome_ug": "sentieon_pangenome_ug.smk",
}
PREP_INPUT_SLURM_RESOURCE_SECTIONS = {
    "prep_input_sample_files": "prep_input_sample_files.smk",
    "roche_downsample_bam": "prep_input_sample_files.smk",
}
SLURM_SUBMIT_RESOURCE_KEYS = {
    "distribution",
    "exclude",
    "include",
    "exclusive",
}


def test_slurm_profile_routes_job_stdout_and_stderr_to_logs() -> None:
    profile = yaml.safe_load(
        (REPO_ROOT / "config/day_profiles/slurm/templates/config.yaml").read_text(
            encoding="utf-8"
        )
    )
    resources = SimpleNamespace(
        time=60,
        partition="i192",
        mem_mb=3000,
        distribution="block",
        constraint="",
        exclude="",
        include="",
        exclusive="",
    )
    params = SimpleNamespace(cluster_sample="HG002")

    rendered = profile["cluster"].format(
        rule="seqfu",
        params=params,
        resources=resources,
        threads=4,
        jobid=12345,
    )
    args = shlex.split(rendered)

    assert "--job-name=seqfu-HG002" in args
    assert "--output=logs/slurm/seqfu/seqfu.HG002.12345.out" in args
    assert "--error=logs/slurm/seqfu/seqfu.HG002.12345.err" in args
    assert not any(
        "--output=logs/slurm" in arg for arg in args if arg.startswith("--job-name")
    )


def test_slurm_profile_default_partition_includes_384_vcpu_queue() -> None:
    profile = yaml.safe_load(
        (REPO_ROOT / "config/day_profiles/slurm/templates/config.yaml").read_text(
            encoding="utf-8"
        )
    )

    assert "partition=i384nvme,i192,i192nvme,i128" in profile["default-resources"]


def test_slurm_rule_config_uses_v8_partitions_and_explicit_memory() -> None:
    rule_config = yaml.safe_load(SLURM_RULE_CONFIG.read_text(encoding="utf-8"))

    def walk(value, context: str) -> None:
        if isinstance(value, dict):
            has_partition = False
            for key, child in value.items():
                if key == "partition" or key.endswith("_partition"):
                    has_partition = True
                    parts = {part for part in str(child).split(",") if part}
                    assert not (parts & RETIRED_PARTITIONS), context
                    assert parts <= V8_PARTITIONS, (context, parts - V8_PARTITIONS)
                walk(child, f"{context}.{key}")
            if has_partition:
                assert "mem_mb" in value, context
        elif isinstance(value, list):
            for index, item in enumerate(value):
                walk(item, f"{context}[{index}]")

    walk(rule_config, "rule_config")


def test_active_rule_files_do_not_hardcode_retired_partitions() -> None:
    hits: list[str] = []
    for path in sorted(ACTIVE_RULES_DIR.glob("*.smk")):
        text = path.read_text(encoding="utf-8")
        for retired in RETIRED_PARTITIONS:
            if retired in text:
                hits.append(f"{path.name}: {retired}")

    assert not hits


def test_pangenome_rules_define_slurm_submit_resources() -> None:
    rule_config = yaml.safe_load(SLURM_RULE_CONFIG.read_text(encoding="utf-8"))
    expected_partitions = "i384nvme,i192nvme,i128nvme"

    for section, rule_file in PANGENOME_SLURM_RESOURCE_SECTIONS.items():
        cfg = rule_config[section]
        assert cfg["threads"] == 128, section
        assert cfg["partition"] == expected_partitions, section
        for key in SLURM_SUBMIT_RESOURCE_KEYS:
            assert key in cfg, f"{section}.{key}"

        text = (ACTIVE_RULES_DIR / rule_file).read_text(encoding="utf-8")
        for key in SLURM_SUBMIT_RESOURCE_KEYS:
            expected = f'{key}=config["{section}"]["{key}"]'
            assert expected in text, f"{rule_file}: {expected}"


def test_prep_input_rules_define_slurm_submit_resources() -> None:
    rule_config = yaml.safe_load(SLURM_RULE_CONFIG.read_text(encoding="utf-8"))
    text = (ACTIVE_RULES_DIR / "prep_input_sample_files.smk").read_text(
        encoding="utf-8"
    )

    for section in PREP_INPUT_SLURM_RESOURCE_SECTIONS:
        cfg = rule_config[section]
        for key in SLURM_SUBMIT_RESOURCE_KEYS:
            assert key in cfg, f"{section}.{key}"
            expected = f"{key}=config['{section}']['{key}']"
            assert expected in text, f"prep_input_sample_files.smk: {expected}"


def test_align_and_dedup_config_use_nvme_partitions_and_scratch_tmp() -> None:
    rule_config = yaml.safe_load(SLURM_RULE_CONFIG.read_text(encoding="utf-8"))
    expected = {"i384nvme", "i192nvme"}

    for section in sorted(ALIGN_DEDUP_CONFIG_SECTIONS):
        value = rule_config[section]["partition"]
        parts = {part for part in str(value).split(",") if part}
        if section == "sentmm2ont_align_sort":
            assert parts == {"i384nvme"}, f"{section}.partition={value}"
            continue
        assert expected <= parts, f"{section}.partition={value}"

    assert rule_config["sent_dedup"]["tmp_base"] == "/scratch"
    assert rule_config["doppelmark"]["mem_mb"] >= 600000


def test_align_and_dedup_rule_shells_do_not_use_dev_shm_tmpdirs() -> None:
    hits: list[str] = []
    for filename in sorted(ALIGN_DEDUP_RULE_FILES):
        text = (ACTIVE_RULES_DIR / filename).read_text(encoding="utf-8")
        if "/dev/shm" in text:
            hits.append(filename)

    assert not hits


def test_slurm_rule_config_uses_valid_openmp_env_vars() -> None:
    path = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
    text = path.read_text(encoding="utf-8")
    rule_config = yaml.safe_load(text)

    assert re.search(r"\bOMP_THREADS=", text) is None
    assert re.search(r"\bOMP_BIND_PROC=", text) is None
    assert "OMP_NUM_THREADS=128" in rule_config["deepvariant_1_9_roche"]["numa"]
    assert "OMP_NUM_THREADS=42" in rule_config["deepsomatic"]["numa"]
    assert "OMP_NUM_THREADS=42" in rule_config["senttn"]["numa"]
