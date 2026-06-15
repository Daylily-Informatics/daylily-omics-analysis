#!/usr/bin/env python3
"""Prepare the full-depth two-sample SMN12 DayOA workdir on dyecX4."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


ANALYSIS_ID = "smn12_full_ilmn_chip124_20260615T092300Z"
REMOTE_ROOT = f"/fsx/analysis_results/dyecX4/{ANALYSIS_ID}"
REMOTE_REPO = f"{REMOTE_ROOT}/daylily-omics-analysis"
CONFIG_S3 = (
    "s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/dyecX4/"
    f"{ANALYSIS_ID}/config"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster", default="dyecX4")
    parser.add_argument("--profile", default="lsmc")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    target = resolve_headnode_instance_id(args.cluster, args.region, profile=args.profile)
    wait_for_ssm_online(target.instance_id, args.region, profile=args.profile, timeout=600)

    script = f"""
set -euo pipefail
echo "__META__	utc	$(date -u +%FT%TZ)"
echo "__META__	analysis_id	{ANALYSIS_ID}"
echo "__META__	preferred_remote_root	{REMOTE_ROOT}"
echo "__META__	config_s3	{CONFIG_S3}"

repo=""
root=""
for candidate in "/fsx/analysis_results/dyecX4/{ANALYSIS_ID}" "/fsx/analysis_results/ubuntu/{ANALYSIS_ID}"; do
  if [[ -d "$candidate/daylily-omics-analysis/.git" ]]; then
    root="$candidate"
    repo="$candidate/daylily-omics-analysis"
  fi
done

if [[ -z "$repo" ]]; then
  if [[ -e "/fsx/analysis_results/dyecX4/{ANALYSIS_ID}" ]] || [[ -e "/fsx/analysis_results/ubuntu/{ANALYSIS_ID}" ]]; then
    echo "__ERROR__	analysis_id_exists_without_repo	{ANALYSIS_ID}"
    exit 20
  fi
  cd /fsx/analysis_results/ubuntu
  day-clone -t jem-dev -d {ANALYSIS_ID}
  for candidate in "/fsx/analysis_results/dyecX4/{ANALYSIS_ID}" "/fsx/analysis_results/ubuntu/{ANALYSIS_ID}"; do
    if [[ -d "$candidate/daylily-omics-analysis/.git" ]]; then
      root="$candidate"
      repo="$candidate/daylily-omics-analysis"
    fi
  done
fi

if [[ -z "$repo" ]]; then
  echo "__ERROR__	repo_not_found_after_clone	{ANALYSIS_ID}"
  exit 21
fi

echo "__META__	actual_remote_root	$root"
echo "__META__	actual_remote_repo	$repo"
cd "$repo"
mkdir -p config logs
aws s3 cp "{CONFIG_S3}/samples.tsv" config/samples.tsv --region {args.region}
aws s3 cp "{CONFIG_S3}/units.tsv" config/units.tsv --region {args.region}
aws s3 cp "{CONFIG_S3}/patch_smn12_runtime.py" config/patch_smn12_runtime.py --region {args.region}
git rev-parse HEAD | tee logs/full_depth_chip124_dayoa_head.txt
git status --short --branch | tee logs/full_depth_chip124_dayoa_status.txt
wc -l config/samples.tsv config/units.tsv
python3 -c "import csv; rows=list(csv.DictReader(open('config/units.tsv'), delimiter='\\t')); print('__UNITS__\\tcount\\t' + str(len(rows))); [print('__UNIT__\\t' + row['SAMPLEID'] + '\\t' + row['RUNID'] + '\\t' + row['LANEID'] + '\\t' + row['BARCODEID'] + '\\tont=' + str(len(row['ONT_R1_PATH'].split(','))) + '\\tilmn_r1=' + row['ILMN_R1_PATH']) for row in rows]; assert len(rows) == 2; assert all('ds20x' not in row['ILMN_R1_PATH'] and 'ds20x' not in row['ILMN_R2_PATH'] for row in rows)"
"""
    result = run_shell(
        target.instance_id,
        args.region,
        script,
        profile=args.profile,
        timeout=900,
        comment="Prepare full-depth SMN12 chip124 DayOA workdir",
    )

    payload = {
        "created_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "analysis_id": ANALYSIS_ID,
        "remote_root": REMOTE_ROOT,
        "remote_repo": REMOTE_REPO,
        "config_s3": CONFIG_S3,
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
