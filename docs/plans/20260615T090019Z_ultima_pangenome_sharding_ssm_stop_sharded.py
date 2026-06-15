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
SAMPLE = "HG00340X-HG003-PILOT23ME-1-Z0383CGATCACAAGCTGAT-PF-UG-ULTIMA"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script(*, session: str) -> str:
    name_prefix = f"sentieon_pangenome_ug_sharded-{SAMPLE}"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        command -v tmux >/dev/null
        command -v squeue >/dev/null
        command -v scancel >/dev/null
        SESSION={q(session)}
        NAME_PREFIX={q(name_prefix)}

        echo "__STOP_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "__CONTROLLER_BEFORE__"
        if tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "present"
          tmux list-windows -t "$SESSION"
          tmux list-panes -t "$SESSION"
          tmux send-keys -t "$SESSION" C-c
          sleep 5
          tmux kill-session -t "$SESSION" || true
        else
          echo "absent"
        fi

        echo "__SHARDED_JOBS_BEFORE_CANCEL__"
        squeue -h -u ubuntu -o "%i|%T|%M|%j|%R" |
          awk -F'|' -v p="$NAME_PREFIX" '$4 ~ p {{print}}' |
          sort -n || true

        mapfile -t job_ids < <(
          squeue -h -u ubuntu -o "%i|%j" |
            awk -F'|' -v p="$NAME_PREFIX" '$2 ~ p {{print $1}}' |
            sort -n
        )
        if [[ "${{#job_ids[@]}}" -gt 0 ]]; then
          printf "__SCANCEL_IDS__=%s\\n" "${{job_ids[*]}}"
          scancel "${{job_ids[@]}}"
        else
          echo "__SCANCEL_IDS__=none"
        fi
        sleep 5

        echo "__CONTROLLER_AFTER__"
        if tmux has-session -t "$SESSION" 2>/dev/null; then echo "present"; else echo "absent"; fi

        echo "__SHARDED_JOBS_AFTER_CANCEL__"
        squeue -h -u ubuntu -o "%i|%T|%M|%j|%R" |
          awk -F'|' -v p="$NAME_PREFIX" '$4 ~ p {{print}}' |
          sort -n || true
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(session=args.session),
            profile=PROFILE,
            timeout=180,
            comment=f"Stop sharded Ultima pangenome run {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
