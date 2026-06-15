#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


INSTANCE_ID = "i-05815cdeec4a6dad8"
REGION = "us-west-2"
PROFILE = "lsmc"


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def build_remote_script(*, session: str, lines: int) -> str:
    run_dir = f"/home/ubuntu/daylily-runs/{session}"
    tmux_log = f"{run_dir}/tmux.log"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={shell_quote(session)}
        TMUX_LOG={shell_quote(tmux_log)}
        echo "__SESSION__=$SESSION"
        if timeout 5s tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "__TMUX_EXISTS__=yes"
        else
          echo "__TMUX_EXISTS__=no"
        fi
        echo "__SQUEUE__"
        timeout 15s squeue -u ubuntu || true
        echo "__PANE__"
        timeout 15s tmux capture-pane -pt "$SESSION" -S -{int(lines)} || true
        echo "__TMUX_LOG_TAIL__"
        if [[ -f "$TMUX_LOG" ]]; then
          timeout 15s tail -n {int(lines)} "$TMUX_LOG" || true
        else
          echo "missing tmux log: $TMUX_LOG"
        fi
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--lines", type=int, default=220)
    args = parser.parse_args()

    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            build_remote_script(session=args.session, lines=args.lines),
            profile=PROFILE,
            timeout=120,
            comment=f"Capture HG003 pangenome session {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
