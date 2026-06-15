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


def remote_script(*, session: str, rename: bool) -> str:
    repo_dir = f"/fsx/analysis_results/ubuntu/{session}/daylily-omics-analysis"
    py = r"""
import os
import re
import subprocess
import sys
from pathlib import Path

repo = Path(os.environ["REPO_DIR"])
rename = os.environ.get("RENAME", "0") == "1"
log_dir = repo / ".snakemake" / "log"
logs = sorted(log_dir.glob("*.snakemake.log"), key=lambda p: p.stat().st_mtime, reverse=True)
if not logs:
    raise SystemExit("no snakemake logs found")
latest = logs[0]
text = latest.read_text(errors="replace")
blocks = re.split(r"\n(?=rule sentieon_pangenome_ug_sharded:)", text)
mapping = {}
for block in blocks:
    if not block.startswith("rule sentieon_pangenome_ug_sharded:"):
        continue
    dchrm = re.search(r"\bdchrm=([^,\n]+)", block)
    sample = re.search(r"\bsample=([^,\n]+)", block)
    external = re.search(r"external jobid '([0-9]+)'", block)
    if dchrm and sample and external:
        mapping[external.group(1)] = (dchrm.group(1), sample.group(1))

squeue = subprocess.run(
    ["squeue", "-h", "-u", "ubuntu", "-o", "%i|%T|%M|%j|%R"],
    check=True,
    text=True,
    stdout=subprocess.PIPE,
)
active = []
for line in squeue.stdout.splitlines():
    parts = line.split("|", 4)
    if len(parts) != 5:
        continue
    jobid, state, elapsed, name, reason = parts
    if "sentieon_pangenome_ug_sharded" in name:
        active.append((jobid, state, elapsed, name, reason))

print(f"__SNAKEMAKE_LOG__={latest}")
print("__JOB_SHARD_MAP__")
for jobid, state, elapsed, name, reason in sorted(active, key=lambda r: int(r[0])):
    dchrm, sample = mapping.get(jobid, ("UNKNOWN", "UNKNOWN"))
    proposed = f"sentieon_pangenome_ug_sharded-{sample}-{dchrm}"
    print(f"{jobid}\t{state}\t{elapsed}\t{dchrm}\t{name}\t{proposed}\t{reason}")

missing = [jobid for jobid, *_ in active if jobid not in mapping]
if missing:
    print("__MISSING_MAPPING__=" + ",".join(sorted(missing, key=int)))
    raise SystemExit(68)

if rename:
    print("__RENAME_ACTIONS__")
    for jobid, state, elapsed, name, reason in sorted(active, key=lambda r: int(r[0])):
        dchrm, sample = mapping[jobid]
        proposed = f"sentieon_pangenome_ug_sharded-{sample}-{dchrm}"
        if name == proposed:
            print(f"{jobid}\talready\t{proposed}")
            continue
        subprocess.run(["scontrol", "update", f"JobId={jobid}", f"Name={proposed}"], check=True)
        print(f"{jobid}\trenamed\t{proposed}")
"""
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        command -v squeue >/dev/null
        command -v scontrol >/dev/null
        export REPO_DIR={q(repo_dir)}
        export RENAME={"1" if rename else "0"}
        python3 -c {q(py)}
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--rename", action="store_true")
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(session=args.session, rename=args.rename),
            profile=PROFILE,
            timeout=180,
            comment=f"Map sharded pangenome Slurm jobs to shard tokens {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
