#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


INSTANCE_ID = "i-05b2743c3c3fffa93"
REGION = "us-west-2"
PROFILE = "lsmc"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script(*, session: str, lines: int) -> str:
    tmux_log = f"/home/ubuntu/daylily-runs/{session}/tmux.log"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        TMUX_LOG={q(tmux_log)}
        echo "__LOG__=$TMUX_LOG"
        echo "__TAIL__"
        tail -n {int(lines)} "$TMUX_LOG"
        echo "__ERROR_CONTEXT__"
        grep -nEi "error|exception|traceback|ambiguous|missinginput|syntax|ruleexception|__DAYOA_FAIL__" "$TMUX_LOG" | tail -n 60 || true
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--lines", type=int, default=80)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(session=args.session, lines=args.lines),
            profile=PROFILE,
            timeout=180,
            comment=f"Tail sharded dry-run log {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
