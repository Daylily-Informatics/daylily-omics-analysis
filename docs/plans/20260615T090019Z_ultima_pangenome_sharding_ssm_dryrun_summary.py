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
    repo_dir = f"/fsx/analysis_results/ubuntu/{session}/daylily-omics-analysis"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(session)}
        TMUX_LOG={q(tmux_log)}
        REPO_DIR={q(repo_dir)}
        echo "__SESSION__=$SESSION"
        echo "__TMUX_EXISTS__"
        if tmux has-session -t "$SESSION" 2>/dev/null; then echo yes; else echo no; fi
        echo "__LOG_EXISTS__"
        test -f "$TMUX_LOG" && ls -lh "$TMUX_LOG"
        echo "__REPO_HEAD__"
        git -C "$REPO_DIR" rev-parse HEAD || true
        echo "__DAYOA_MARKERS__"
        grep -nE "__DAYOA_|__DAYLILY_|AUTO-CONFIG" "$TMUX_LOG" || true
        echo "__FAIL_MARKERS__"
        grep -n "__DAYOA_FAIL__" "$TMUX_LOG" || true
        echo "__RULE_MARKERS__"
        grep -nE "rule sentieon_pangenome_ug_shard_bed:|rule sentieon_pangenome_ug_sharded:|localrule sentpgs_concat_fofn:|rule sentpgs_concat_index_chunks:|rule produce_pangenome_ug_sharded_vcf:|rule produce_snv_concordances:" "$TMUX_LOG" || true
        echo "__SENTPGS_PATH_MARKERS__"
        grep -n "snv/sentpgs" "$TMUX_LOG" | tail -n {int(lines)} || true
        echo "__SENTPG_PATH_MARKERS__"
        grep -n "snv/sentpg/" "$TMUX_LOG" || true
        echo "__LOG_TAIL__"
        tail -n {int(lines)} "$TMUX_LOG"
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--lines", type=int, default=120)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(session=args.session, lines=args.lines),
            profile=PROFILE,
            timeout=180,
            comment=f"Summarize sharded dry-run {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
