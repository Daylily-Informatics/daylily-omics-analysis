#!/usr/bin/env python3
"""Launch NA00232 chip124 DayOA live run in an ubuntu tmux session."""

from __future__ import annotations

import argparse
import base64
import json
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


ANALYSIS_ID = "na00232_smn12_chip124_20260615T062929Z"
REMOTE_REPO = f"/fsx/analysis_results/dyecX4/{ANALYSIS_ID}/daylily-omics-analysis"
SESSION = "dayoa_na00232_smn12_chip124_20260615T062929Z_live"
LIVE_LOG = "logs/live_smn12_chip124_20260615T062929Z.log"
PATCH_LOG = "logs/smn12_runtime_patch_chip124_live_20260615T062929Z.log"
DRYRUN_LOG = "logs/dryrun_smn12_chip124_20260615T062929Z.log"
TARGETS = "produce_smn12_orthogonal_calls produce_htd_calls produce_sentdhiomr_segdup"
FLAGS = "-p -T 0 -k -j 500 --rerun-triggers mtime"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster", default="dyecX4")
    parser.add_argument("--profile", default="lsmc")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    target = resolve_headnode_instance_id(args.cluster, args.region, profile=args.profile)
    wait_for_ssm_online(target.instance_id, args.region, profile=args.profile, timeout=600)

    live_cmd = (
        f"dy-r {TARGETS} {FLAGS} 2>&1 | tee {LIVE_LOG}; "
        "rc=${PIPESTATUS[0]}; "
        f"echo __LIVE_RC__=$rc | tee -a {LIVE_LOG}; "
        "exit $rc"
    )
    live_cmd_b64 = base64.b64encode(live_cmd.encode("utf-8")).decode("ascii")

    script = f"""
set -euo pipefail
repo="{REMOTE_REPO}"
session="{SESSION}"
if [[ ! -d "$repo/.git" ]]; then
  echo "__ERROR__	repo_missing	$repo"
  exit 21
fi
if ! grep -q "__DRYRUN_RC__=0" "$repo/{DRYRUN_LOG}"; then
  echo "__ERROR__	dryrun_success_marker_missing	$repo/{DRYRUN_LOG}"
  exit 22
fi
if [[ -s "$repo/{LIVE_LOG}" ]]; then
  echo "__ERROR__	live_log_exists	$repo/{LIVE_LOG}"
  exit 23
fi
if tmux has-session -t "$session" 2>/dev/null; then
  echo "__ERROR__	tmux_session_exists	$session"
  exit 24
fi
mkdir -p "$repo/logs"
tmux new-session -d -s "$session" -c "$repo" bash -il
sleep 1
tmux send-keys -t "$session" "cd $repo" C-m
sleep 1
tmux send-keys -t "$session" "source dyoainit" C-m
sleep 2
tmux send-keys -t "$session" "dy-a slurm hg38_broad" C-m
sleep 2
tmux send-keys -t "$session" "python config/patch_smn12_runtime.py 2>&1 | tee {PATCH_LOG}" C-m
sleep 2
tmux send-keys -t "$session" "set -o pipefail" C-m
sleep 1
live_cmd=$(python3 -c "import base64; print(base64.b64decode('{live_cmd_b64}').decode())")
tmux send-keys -t "$session" "$live_cmd" C-m
echo "__TMUX_SESSION__	$session"
echo "__REMOTE_REPO__	$repo"
echo "__LIVE_LOG__	$repo/{LIVE_LOG}"
"""
    result = run_shell(
        target.instance_id,
        args.region,
        script,
        profile=args.profile,
        timeout=120,
        comment="Launch NA00232 chip124 DayOA live tmux",
    )

    payload = {
        "created_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "analysis_id": ANALYSIS_ID,
        "remote_repo": REMOTE_REPO,
        "session": SESSION,
        "targets": TARGETS,
        "flags": FLAGS,
        "live_log": f"{REMOTE_REPO}/{LIVE_LOG}",
        "patch_log": f"{REMOTE_REPO}/{PATCH_LOG}",
        "cluster": args.cluster,
        "profile": args.profile,
        "region": args.region,
        "instance_id": target.instance_id,
        "command_id": result.command_id,
        "status": result.status,
        "response_code": result.response_code,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
