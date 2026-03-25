#!/usr/bin/env python3
"""Run the local fleet monitor on a headnode and collect workflow status."""

from __future__ import annotations

import argparse
import pathlib
import shlex
import subprocess
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload bin/monitor_ifx_go.sh to a headnode and collect job/log status."
    )
    parser.add_argument("--pem", required=True, help="Path to SSH PEM file")
    parser.add_argument("--host", required=True, help="SSH host, e.g. ubuntu@1.2.3.4")
    parser.add_argument(
        "--base-path",
        default="/fsx/analysis_results/ubuntu",
        help="Remote analysis base path",
    )
    parser.add_argument(
        "--analysis-dir",
        default="ifx_go",
        help="Directory under --base-path containing the active analysis",
    )
    parser.add_argument(
        "--repo-dirname",
        default="daylily-omics-analysis",
        help="Repo directory name nested inside the analysis directory",
    )
    parser.add_argument(
        "--monitor-script",
        default="bin/monitor_ifx_go.sh",
        help="Local monitor script to upload before running",
    )
    return parser.parse_args()


def run_remote(args: argparse.Namespace, cmd: str, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    remote = f"bash -l -c {shlex.quote(cmd)}"
    return subprocess.run(
        ["ssh", "-i", args.pem, args.host, remote],
        text=True,
        input=stdin,
        capture_output=True,
    )


def emit(title: str, proc: subprocess.CompletedProcess[str]) -> int:
    print(f"=== {title} ===")
    if proc.stdout:
        print(proc.stdout.rstrip())
    if proc.stderr:
        print(proc.stderr.rstrip())
    print()
    return proc.returncode


def main() -> int:
    args = parse_args()
    monitor_script = pathlib.Path(args.monitor_script)
    if not monitor_script.is_file():
        print(f"ERROR: local monitor script not found: {monitor_script}", file=sys.stderr)
        return 1

    analysis_root = f"{args.base_path}/{args.analysis_dir}"
    repo_root = f"{analysis_root}/{args.repo_dirname}"
    rc = 0

    upload = run_remote(
        args,
        "cat > /tmp/monitor_ifx_go.sh && chmod +x /tmp/monitor_ifx_go.sh",
        stdin=monitor_script.read_text(),
    )
    rc = max(rc, emit("UPLOAD MONITOR SCRIPT", upload))
    if upload.returncode != 0:
        return upload.returncode

    fleet = run_remote(args, f"/tmp/monitor_ifx_go.sh --base-path {shlex.quote(args.base_path)}")
    rc = max(rc, emit("FLEET MONITOR", fleet))

    layout_cmd = (
        "set -euo pipefail; "
        f"ls -la {shlex.quote(analysis_root)}; "
        "echo ---; "
        f"find {shlex.quote(analysis_root)} -maxdepth 2 -type d "
        "\\( -name .snakemake -o -name logs -o -name config -o -name daylily-omics-analysis \\) | sort"
    )
    rc = max(rc, emit("WORKDIR LAYOUT", run_remote(args, layout_cmd)))

    jobs_cmd = (
        "set -euo pipefail; command -v squeue >/dev/null; "
        "echo JOBID_LONG_JOB_NAME; "
        "squeue -h -u ubuntu -o '%A\t%j'"
    )
    rc = max(rc, emit("SLURM JOBS", run_remote(args, jobs_cmd)))

    snakemake_cmd = (
        "set -euo pipefail; "
        f"latest=$(ls -t {shlex.quote(repo_root)}/.snakemake/log/* 2>/dev/null | head -1 || true); "
        'echo "LOG:$latest"; '
        'if [ -n "$latest" ]; then tail -60 "$latest"; else echo NO_SNAKEMAKE_LOG; fi'
    )
    rc = max(rc, emit("SNAKEMAKE LOG", run_remote(args, snakemake_cmd)))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())