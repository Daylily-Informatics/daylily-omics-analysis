#!/usr/bin/env python3
"""Compact poll for full-depth SMN12 chip124 DayOA state."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


REMOTE_REPO = (
    "/fsx/analysis_results/dyecX4/"
    "smn12_full_ilmn_chip124_20260615T092300Z/daylily-omics-analysis"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster", default="dyecX4")
    parser.add_argument("--profile", default="lsmc")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--session", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    target = resolve_headnode_instance_id(args.cluster, args.region, profile=args.profile)
    wait_for_ssm_online(target.instance_id, args.region, profile=args.profile, timeout=300)

    remote_log = f"{REMOTE_REPO}/{args.log}"
    script = f"""
set -u
repo="{REMOTE_REPO}"
session="{args.session}"
log="{remote_log}"
echo "__META__	utc	$(date -u +%FT%TZ)"
echo "__META__	repo	$repo"
echo "__META__	session	$session"
echo "__META__	log	$log"
if tmux has-session -t "$session" 2>/dev/null; then
  echo "__TMUX__	present"
else
  echo "__TMUX__	absent"
fi
if [[ -f "$log" ]]; then
  echo "__LOG__	present	$(wc -c < "$log")"
  grep -E "__DRYRUN_RC__|__LIVE_RC__|RETURN CODE|WorkflowError|Error|Job stats|total|steps \\(" "$log" | tail -n 40 || true
else
  echo "__LOG__	missing	$log"
fi
echo "__SQUEUE_BEGIN__"
squeue -u ubuntu -o "%.18i %.9P %.24j %.8u %.2t %.10M %.10l %.6D %R" 2>/dev/null | head -n 80 || true
echo "__SQUEUE_END__"
echo "__JOB_LOGS_BEGIN__"
find "$repo/results/day/hg38_broad" -type f \( \
  -path "*align/sentmm2ont/logs/*.sentmm2ont_sort.log" -o \
  -path "*align/sentdhiomr/logs/*.sentdhiomr_sr_align.log" -o \
  -path "*align/sentdhiomr/logs/*.sentdhiomr_sr_markdup.log" -o \
  -path "*align/sentmm2ont/na/htd/hapsma/logs/*.hapsma.log" -o \
  -path "*align/sentmm2ont/na/segdup/sentdhiomr/logs/*.segdup.log" -o \
  -name "*sentdhiomr*.log" \
\) -print 2>/dev/null | sort | while read -r f; do
  echo "__JOB_LOG__	$(wc -c < "$f")	$f"
  tail -n 5 "$f" 2>/dev/null || true
done
echo "__JOB_LOGS_END__"
exit 0
"""
    result = run_shell(
        target.instance_id,
        args.region,
        script,
        profile=args.profile,
        timeout=120,
        comment="Compact poll full-depth SMN12 chip124 DayOA state",
    )
    payload = {
        "created_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cluster": args.cluster,
        "profile": args.profile,
        "region": args.region,
        "instance_id": target.instance_id,
        "command_id": result.command_id,
        "status": result.status,
        "response_code": result.response_code,
        "session": args.session,
        "log": remote_log,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
