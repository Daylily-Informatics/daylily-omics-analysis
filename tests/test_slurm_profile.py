from __future__ import annotations

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

    assert (
        "partition=i192,i128,i192mem,bcl2fq-i384-nvme-test"
        in profile["default-resources"]
    )
