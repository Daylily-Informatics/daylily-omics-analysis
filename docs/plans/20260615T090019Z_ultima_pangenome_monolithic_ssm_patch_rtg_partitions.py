#!/usr/bin/env python3
from __future__ import annotations

import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


INSTANCE_ID = "i-05b2743c3c3fffa93"
REGION = "us-west-2"
PROFILE = "lsmc"
SESSION = "altair_hg003_ultima_pg_20260615T052434Z"
REPO = f"/fsx/analysis_results/ubuntu/{SESSION}/daylily-omics-analysis"
RTG_PARTITIONS = "i384nvme,i192hugenvme,i192nvme,i192,i128nvme,i128"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script() -> str:
    py = r"""
import os
from pathlib import Path

repo = Path(os.environ["REPO"])
partitions = os.environ["RTG_PARTITIONS"]
paths = [
    repo / "config/day_profiles/slurm/rule_config.yaml",
    repo / "config/day_profiles/slurm/templates/rule_config.yaml",
]
section_keys = {
    "prep_for_concordance_check": ("partition",),
    "rtg_vcfeval": ("partition", "partition_other"),
    "run_concordance": ("partition",),
    "roche_rtg_vcfeval": ("partition",),
}

for path in paths:
    lines = path.read_text().splitlines()
    current_section = None
    for idx, line in enumerate(lines):
        if line and not line.startswith(" ") and line.endswith(":"):
            current_section = line[:-1]
            continue
        if current_section not in section_keys:
            continue
        stripped = line.strip()
        for key in section_keys[current_section]:
            if stripped.startswith(f"{key}:"):
                indent = line[: len(line) - len(line.lstrip())]
                lines[idx] = f"{indent}{key}: {partitions}"
    text = "\n".join(lines) + "\n"
    for section, keys in section_keys.items():
        for key in keys:
            needle = f"{section}:"
            if needle not in text:
                raise SystemExit(f"missing section {section} in {path}")
    path.write_text(text)

for path in paths:
    print(f"__PATCHED__={path}")
    lines = path.read_text().splitlines()
    current_section = None
    for line in lines:
        if line and not line.startswith(" ") and line.endswith(":"):
            current_section = line[:-1]
        if current_section in section_keys and line.strip().startswith(("partition:", "partition_other:")):
            print(f"{current_section}.{line.strip()}")
"""
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        export REPO={q(REPO)}
        export RTG_PARTITIONS={q(RTG_PARTITIONS)}
        echo "__PATCH_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        python3 -c {q(py)}
        """
    ).strip()


def main() -> None:
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(),
            profile=PROFILE,
            timeout=180,
            comment="Patch monolithic workset RTG concordance partitions",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
