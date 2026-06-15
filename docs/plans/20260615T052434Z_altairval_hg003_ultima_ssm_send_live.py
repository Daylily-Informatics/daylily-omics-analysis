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
CLONE_ROOT = "/fsx/analysis_results/ubuntu"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script(*, analysis_id: str, session: str) -> str:
    repo_dir = f"{CLONE_ROOT}/{analysis_id}/daylily-omics-analysis"
    live_run = "dy-r produce_pangenome_ug_vcf -p -j 150 -k -T 0 --rerun-triggers mtime"
    commands = [
        f"cd {q(repo_dir)}",
        "echo __DAYOA_STAGE__=live_run_start $(date --iso-8601=seconds)",
        (
            f"{live_run}; live_rc=$?; "
            "if [[ $live_rc -ne 0 ]]; then echo __DAYOA_FAIL__=live_run rc=$live_rc $(date --iso-8601=seconds); "
            "else echo __DAYOA_STAGE__=live_run_done rc=0 $(date --iso-8601=seconds); fi"
        ),
    ]
    send_lines = "\n".join(
        f"tmux send-keys -t \"$SESSION\" {q(command)} C-m"
        for command in commands
    )
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(session)}
        REPO_DIR={q(repo_dir)}
        test "$(id -un)" = ubuntu
        if ! tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "missing tmux session: $SESSION" >&2
          exit 64
        fi
        window_count=$(tmux list-windows -t "$SESSION" | wc -l | tr -d ' ')
        pane_count=$(tmux list-panes -t "$SESSION" | wc -l | tr -d ' ')
        if [[ "$window_count" != "1" || "$pane_count" != "1" ]]; then
          echo "unexpected tmux shape for $SESSION: windows=$window_count panes=$pane_count" >&2
          exit 66
        fi
        if [[ ! -d "$REPO_DIR" ]]; then
          echo "missing analysis repo directory: $REPO_DIR" >&2
          exit 65
        fi
        {send_lines}
        echo "__DAYLILY_SENT_LIVE__=$SESSION"
        echo "__DAYLILY_ANALYSIS_DIR__=$REPO_DIR"
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-id", required=True)
    parser.add_argument("--session", required=True)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(analysis_id=args.analysis_id, session=args.session),
            profile=PROFILE,
            timeout=180,
            comment=f"Send live altairval HG003 Ultima commands {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
