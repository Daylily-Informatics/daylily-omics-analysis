from __future__ import annotations

import re
import shlex
from pathlib import Path
from types import SimpleNamespace

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


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

    assert "partition=i192,i128,i384nvme,i192nvme" in profile["default-resources"]


def test_slurm_rule_config_uses_v8_partitions_and_explicit_memory() -> None:
    path = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
    rule_config = yaml.safe_load(path.read_text(encoding="utf-8"))
    allowed = {"i8", "i128", "i192", "i128nvme", "i192nvme", "i384nvme", "i192hugenvme"}
    retired = {"i192mem", "i192bigmem", "bcl-convert", "bcl2fq-i192-nvme-test", "bcl2fq-i384-nvme-test"}

    def walk(value, context: str) -> None:
        if isinstance(value, dict):
            has_partition = False
            for key, child in value.items():
                if key == "partition" or key.endswith("_partition"):
                    has_partition = True
                    parts = {part for part in str(child).split(",") if part}
                    assert not (parts & retired), context
                    assert parts <= allowed, (context, parts - allowed)
                walk(child, f"{context}.{key}")
            if has_partition:
                assert "mem_mb" in value, context
        elif isinstance(value, list):
            for index, item in enumerate(value):
                walk(item, f"{context}[{index}]")

    walk(rule_config, "rule_config")


def test_slurm_rule_config_uses_valid_openmp_env_vars() -> None:
    path = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
    text = path.read_text(encoding="utf-8")
    rule_config = yaml.safe_load(text)

    assert re.search(r"\bOMP_THREADS=", text) is None
    assert re.search(r"\bOMP_BIND_PROC=", text) is None
    assert "OMP_NUM_THREADS=128" in rule_config["deepvariant_1_9_roche"]["numa"]
    assert "OMP_NUM_THREADS=42" in rule_config["deepsomatic"]["numa"]
    assert "OMP_NUM_THREADS=42" in rule_config["senttn"]["numa"]
