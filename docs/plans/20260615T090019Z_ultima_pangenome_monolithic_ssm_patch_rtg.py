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
path = repo / "workflow/rules/rtg_vcfeval.smk"
text = path.read_text()
old = 'RTG_MEM="${rtg_mem_gb}G"'
new = 'RTG_MEM="${{rtg_mem_gb}}G"'
if new not in text:
    if old not in text:
        raise SystemExit(f"neither escaped nor unescaped RTG_MEM assignment found in {path}")
    text = text.replace(old, new, 1)
    path.write_text(text)
text = path.read_text()
print("__RTG_ESCAPED__=" + str(new in text))
print("__RTG_UNESCAPED__=" + str(old in text))
"""
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        export REPO={q(REPO)}
        echo "__PATCH_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        python3 -c {q(py)}
        grep -n 'RTG_MEM=' {q(REPO)}/workflow/rules/rtg_vcfeval.smk
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
            comment="Patch monolithic workset RTG shell escaping",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
