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


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script() -> str:
    py = r"""
import os
from pathlib import Path

repo = Path(os.environ["REPO"])
paths = [
    repo / "config/day_profiles/slurm/config.yaml",
    repo / "config/day_profiles/slurm/templates/config.yaml",
]
for path in paths:
    text = path.read_text()
    if "  - time=240" not in text:
        text = text.replace("  - time=200", "  - time=240")
    if "  - time=240" not in text:
        raise SystemExit(f"failed to set time=240 in {path}")
    path.write_text(text)

rtg = (repo / "workflow/rules/rtg_vcfeval.smk").read_text()
print("__RTG_ESCAPED__=" + str('RTG_MEM="${{rtg_mem_gb}}G"' in rtg))
print("__RTG_UNESCAPED__=" + str('RTG_MEM="${rtg_mem_gb}G"' in rtg))
"""
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        export REPO={q(REPO)}
        echo "__PATCH_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        python3 -c {q(py)}
        echo "__PROFILE_CONFIG_TIME__"
        grep -n 'time=' {q(REPO)}/config/day_profiles/slurm/config.yaml
        echo "__TEMPLATE_CONFIG_TIME__"
        grep -n 'time=' {q(REPO)}/config/day_profiles/slurm/templates/config.yaml
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
            comment="Patch monolithic workset Slurm time to 240",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
