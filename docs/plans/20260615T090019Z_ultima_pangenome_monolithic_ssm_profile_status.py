#!/usr/bin/env python3
from __future__ import annotations
import shlex, sys, textwrap
sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")
from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell
INSTANCE_ID="i-05b2743c3c3fffa93"
REGION="us-west-2"
PROFILE="lsmc"
SESSION="altair_hg003_ultima_pg_20260615T052434Z"
REPO=f"/fsx/analysis_results/ubuntu/{SESSION}/daylily-omics-analysis"
def q(v: str) -> str: return shlex.quote(v)
def remote_script() -> str:
    return textwrap.dedent(f"""
    set -euo pipefail
    test "$(id -un)" = ubuntu
    echo "__POLL_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "__PROFILE_CONFIG_TIME__"
    grep -n 'time=' {q(REPO)}/config/day_profiles/slurm/config.yaml || true
    echo "__TEMPLATE_CONFIG_TIME__"
    grep -n 'time=' {q(REPO)}/config/day_profiles/slurm/templates/config.yaml || true
    echo "__RTG_CONFIG__"
    grep -n -A20 '^rtg_vcfeval:' {q(REPO)}/config/day_profiles/slurm/rule_config.yaml | sed -n '1,60p' || true
    echo "__REPO_HEAD__"
    git -C {q(REPO)} rev-parse HEAD
    """).strip()
def main() -> None:
    try:
        result=run_shell(INSTANCE_ID, REGION, remote_script(), profile=PROFILE, timeout=180, comment="Check monolithic profile time")
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end=""); print(exc.result.stderr, end="", file=sys.stderr); raise
    print(result.stdout, end=""); print(result.stderr, end="", file=sys.stderr)
if __name__=="__main__": main()
