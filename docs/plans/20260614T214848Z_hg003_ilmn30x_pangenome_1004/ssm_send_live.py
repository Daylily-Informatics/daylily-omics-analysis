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
CLONE_ROOT = "/fsx/analysis_results/ubuntu"


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def build_remote_script(*, analysis_id: str, session: str) -> str:
    repo_dir = f"{CLONE_ROOT}/{analysis_id}/daylily-omics-analysis"
    pangenome_live = (
        "dy-r produce_pangenome_sr_vcf produce_snv_concordances "
        "-p -j 150 -k -T 0 --rerun-triggers mtime "
        "--config 'aligners=[\"pangenome_sr\"]' 'snv_callers=[\"sentpg\"]'"
    )
    alignstats_live = (
        "dy-r produce_sent_align produce_dmd_dedup_cram produce_alignstats "
        "-p -j 150 -k -T 0 --rerun-triggers mtime "
        "--config 'aligners=[\"sent\"]' 'dedupers=[\"dppl\"]'"
    )
    commands = [
        f"cd {shell_quote(repo_dir)}",
        "echo __DAYOA_STAGE__=pangenome_live_start $(date --iso-8601=seconds)",
        (
            f"{pangenome_live}; pg_rc=$?; "
            "if [[ $pg_rc -ne 0 ]]; then echo __DAYOA_FAIL__=pangenome_live rc=$pg_rc $(date --iso-8601=seconds); fi"
        ),
        "echo __DAYOA_STAGE__=pangenome_live_done rc=$pg_rc $(date --iso-8601=seconds)",
        "echo __DAYOA_STAGE__=alignstats_live_start $(date --iso-8601=seconds)",
        (
            f"{alignstats_live}; aln_rc=$?; "
            "if [[ $aln_rc -ne 0 ]]; then echo __DAYOA_FAIL__=alignstats_live rc=$aln_rc $(date --iso-8601=seconds); fi"
        ),
        "echo __DAYOA_STAGE__=alignstats_live_done rc=$aln_rc $(date --iso-8601=seconds)",
        (
            "if [[ ${pg_rc:-999} -ne 0 || ${aln_rc:-999} -ne 0 ]]; then "
            "echo __DAYOA_LIVE_DONE__ status=failure pg_rc=${pg_rc:-999} aln_rc=${aln_rc:-999} $(date --iso-8601=seconds); "
            "else echo __DAYOA_LIVE_DONE__ status=success pg_rc=0 aln_rc=0 $(date --iso-8601=seconds); fi"
        ),
    ]
    send_lines = "\n".join(
        f"tmux send-keys -t \"$SESSION\" {shell_quote(command)} C-m"
        for command in commands
    )
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={shell_quote(session)}
        REPO_DIR={shell_quote(repo_dir)}
        test "$(id -un)" = ubuntu
        if ! tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "missing tmux session: $SESSION" >&2
          exit 64
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
            build_remote_script(analysis_id=args.analysis_id, session=args.session),
            profile=PROFILE,
            timeout=120,
            comment=f"Send live HG003 pangenome commands {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
