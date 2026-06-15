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
CRAM = "/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram"
CRAI = f"{CRAM}.crai"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script() -> str:
    return textwrap.dedent(
        f"""
        set -euo pipefail
        echo "__USER__=$(id -un)"
        echo "__HOST__=$(hostname)"
        echo "__COMMANDS__"
        command -v tmux
        command -v day-clone
        command -v squeue
        echo "__HG003_INPUTS__"
        test -f {q(CRAM)}
        test -f {q(CRAI)}
        ls -lh {q(CRAM)} {q(CRAI)}
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
            comment="Preflight altairval HG003 Ultima pangenome inputs",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
