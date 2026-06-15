#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import pathlib
import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


PLAN_DIR = pathlib.Path(__file__).resolve().parent
INSTANCE_ID = "i-05b2743c3c3fffa93"
REGION = "us-west-2"
PROFILE = "lsmc"
DEFAULT_REF = "codex/ultima-pangenome-sharding"
CLONE_ROOT = "/fsx/analysis_results/ubuntu"
CRAM = "/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram"
CRAI = f"{CRAM}.crai"


def b64_text(path: pathlib.Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def q(value: str) -> str:
    return shlex.quote(value)


def checked(command: str, label: str) -> str:
    return (
        f"{command}; rc=$?; "
        f"if [[ $rc -ne 0 ]]; then echo __DAYOA_FAIL__={label} rc=$rc $(date --iso-8601=seconds); exit $rc; fi"
    )


def remote_script(*, analysis_id: str, session: str, ref: str) -> str:
    repo_dir = f"{CLONE_ROOT}/{analysis_id}/daylily-omics-analysis"
    run_dir = f"/home/ubuntu/daylily-runs/{session}"
    samples_b64 = b64_text(PLAN_DIR / "20260615T052434Z_altairval_hg003_ultima_samples.tsv")
    units_b64 = b64_text(PLAN_DIR / "20260615T052434Z_altairval_hg003_ultima_units.tsv")
    dry_run = (
        "dy-r produce_pangenome_ug_sharded_vcf produce_snv_concordances "
        "-p -j 150 -k -T 0 --rerun-triggers mtime -n"
    )
    commands = [
        "set -o pipefail",
        f"export PS1='[{session}]$ '",
        checked(f"test -f {q(CRAM)}", "missing_cram"),
        checked(f"test -f {q(CRAI)}", "missing_crai"),
        checked(f"cd {q(CLONE_ROOT)}", "cd_clone_root"),
        checked(
            f"day-clone -t {q(ref)} -d {q(analysis_id)} --executing-entity ubuntu --repository daylily-omics-analysis",
            "day_clone",
        ),
        checked(f"cd {q(repo_dir)}", "cd_repo"),
        checked(
            f"mkdir -p config && cp {q(run_dir + '/samples.tsv')} config/samples.tsv && cp {q(run_dir + '/units.tsv')} config/units.tsv",
            "copy_manifests",
        ),
        checked("source dyoainit --skip-project-check", "dyoainit"),
        checked("dy-a slurm hg38_broad", "dy_a"),
        "echo __DAYOA_STAGE__=dry_run_start $(date --iso-8601=seconds)",
        checked(dry_run, "dry_run"),
        "echo __DAYOA_STAGE__=dry_run_done $(date --iso-8601=seconds)",
        "echo __DAYOA_READY_FOR_LIVE__=yes $(date --iso-8601=seconds)",
    ]
    send_lines = "\n".join(f"tmux send-keys -t \"$SESSION\" {q(command)} C-m" for command in commands)
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(session)}
        ANALYSIS_ID={q(analysis_id)}
        export RUN_DIR={q(run_dir)}
        REPO_DIR={q(repo_dir)}
        TMUX_LOG="$RUN_DIR/tmux.log"

        test "$(id -un)" = ubuntu
        command -v day-clone
        command -v tmux
        command -v squeue
        if tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "tmux session already exists: $SESSION" >&2
          exit 64
        fi
        if [[ -e {q(CLONE_ROOT)}/"$ANALYSIS_ID" ]]; then
          echo "analysis directory already exists: {CLONE_ROOT}/$ANALYSIS_ID" >&2
          exit 65
        fi

        mkdir -p "$RUN_DIR"
        printf '\\n__DAYOA_LAUNCH__=%s ref=%s started=%s\\n' "$SESSION" {q(ref)} "$(date --iso-8601=seconds)" >> "$TMUX_LOG"
        export SAMPLES_B64={q(samples_b64)}
        export UNITS_B64={q(units_b64)}
        python3 -c 'import base64, os, pathlib; run_dir = pathlib.Path(os.environ["RUN_DIR"]); (run_dir / "samples.tsv").write_bytes(base64.b64decode(os.environ["SAMPLES_B64"])); (run_dir / "units.tsv").write_bytes(base64.b64decode(os.environ["UNITS_B64"]))'

        tmux new-session -d -s "$SESSION" 'bash -il'
        tmux pipe-pane -o -t "$SESSION" "cat >> '$TMUX_LOG'"
        {send_lines}

        echo "__DAYLILY_SESSION__=$SESSION"
        echo "__DAYLILY_ANALYSIS_DIR__=$REPO_DIR"
        echo "__DAYLILY_TMUX_LOG__=$TMUX_LOG"
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-id", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--ref", default=DEFAULT_REF)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(analysis_id=args.analysis_id, session=args.session, ref=args.ref),
            profile=PROFILE,
            timeout=180,
            comment=f"Launch altairval HG003 sharded Ultima dry-run {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
