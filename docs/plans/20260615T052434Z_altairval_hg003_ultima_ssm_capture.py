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
    run_dir = f"/home/ubuntu/daylily-runs/{session}"
    tmux_log = f"{run_dir}/tmux.log"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(session)}
        TMUX_LOG={q(tmux_log)}
        echo "__SESSION__=$SESSION"
        if timeout 5s tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "__TMUX_EXISTS__=yes"
          echo "__TMUX_WINDOWS__"
          tmux list-windows -t "$SESSION" || true
          echo "__TMUX_PANES__"
          tmux list-panes -t "$SESSION" || true
        else
          echo "__TMUX_EXISTS__=no"
        fi
        echo "__SQUEUE__"
        timeout 20s squeue -u ubuntu || true
        echo "__PANE__"
        timeout 20s tmux capture-pane -pt "$SESSION" -S -{int(lines)} || true
        echo "__TMUX_LOG_TAIL__"
        if [[ -f "$TMUX_LOG" ]]; then
          timeout 20s tail -n {int(lines)} "$TMUX_LOG" || true
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
            remote_script(session=args.session, lines=args.lines),
            profile=PROFILE,
            timeout=180,
            comment=f"Capture altairval HG003 Ultima session {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
