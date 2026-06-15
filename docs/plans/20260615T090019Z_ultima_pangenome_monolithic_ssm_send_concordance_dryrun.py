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
    dry_run = (
        "dy-r produce_pangenome_ug_vcf produce_snv_concordances -p -j 150 -k -T 0 "
        "--rerun-triggers mtime -n"
    )
    commands = [
        f"cd {q(REPO)}",
        "source dyoainit --skip-project-check",
        "dy-a slurm hg38_broad",
        "echo __DAYOA_STAGE__=monolithic_concordance_dryrun_start $(date --iso-8601=seconds)",
        (
            f"{dry_run}; dry_rc=$?; "
            "if [[ $dry_rc -ne 0 ]]; then echo __DAYOA_FAIL__=monolithic_concordance_dryrun rc=$dry_rc $(date --iso-8601=seconds); "
            "else echo __DAYOA_STAGE__=monolithic_concordance_dryrun_done rc=0 $(date --iso-8601=seconds); fi"
        ),
    ]
    send_lines = "\n".join(f"tmux send-keys -t \"$SESSION\" {q(cmd)} C-m" for cmd in commands)
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        command -v tmux >/dev/null
        SESSION={q(SESSION)}
        REPO={q(REPO)}
        test -d "$REPO"
        if ! tmux has-session -t "$SESSION" 2>/dev/null; then
          tmux new-session -d -s "$SESSION" 'bash -il'
        fi
        window_count=$(tmux list-windows -t "$SESSION" | wc -l | tr -d ' ')
        pane_count=$(tmux list-panes -t "$SESSION" | wc -l | tr -d ' ')
        if [[ "$window_count" != "1" || "$pane_count" != "1" ]]; then
          echo "unexpected tmux shape for $SESSION: windows=$window_count panes=$pane_count" >&2
          exit 66
        fi
        {send_lines}
        echo "__SENT_DRYRUN__=$SESSION"
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
            comment="Send monolithic sentpg concordance dry-run",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
