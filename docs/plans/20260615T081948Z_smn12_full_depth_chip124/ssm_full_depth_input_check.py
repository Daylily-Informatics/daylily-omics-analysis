#!/usr/bin/env python3
"""Verify exact full-depth ILMN and chip1+2+4 ONT inputs on the headnode."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


SCRIPT = r'''
set -u
printf "__META__\tutc\t%s\n" "$(date -u +%FT%TZ)"
printf "__META__\thostname\t%s\n" "$(hostname)"
printf "__META__\tuser\t%s\n" "$(id -un)"

printf "__SECTION__\tactive_state\n"
squeue -u ubuntu -o '__SQUEUE__	%i	%T	%j	%M	%l	%D	%R' 2>&1 || true
ps -eo pid,ppid,stat,etime,args \
  | grep -E 'dy-r|day_run|snakemake|dyec export|fsx_export|data-repository|sentieon|segdup-caller|rtg|vcfeval|dnascope|sentdhiomr|sentpg|dayoa_' \
  | grep -v grep \
  | sed 's/^/__PROC__\t/' || true

printf "__SECTION__\tfull_depth_ilmn\n"
for fq in \
  /fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA00232-SMN_S46_R1_001.fastq.gz \
  /fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA00232-SMN_S46_R2_001.fastq.gz \
  /fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA09677-SMN_S47_R1_001.fastq.gz \
  /fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA09677-SMN_S47_R2_001.fastq.gz; do
  if [[ -s "$fq" ]]; then
    printf "__ILMN_FULL__\t%s\t%s\n" "$(stat -c '%s' "$fq")" "$fq"
  else
    printf "__ILMN_FULL_MISSING__\t%s\n" "$fq"
  fi
done

printf "__SECTION__\tchip124_ont\n"
for sample_barcode in barcode18 barcode19; do
  for chip in chip1 chip2 chip4; do
    dir="/fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ont/${chip}/fastq_pass/${sample_barcode}"
    if [[ -d "$dir" ]]; then
      count=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | wc -l | tr -d ' ')
      bytes=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
      printf "__ONT_CHIP__\t%s\t%s\t%s\t%s\t%s\n" "$sample_barcode" "$chip" "$count" "$bytes" "$dir"
    else
      printf "__ONT_CHIP_MISSING__\t%s\t%s\t%s\n" "$sample_barcode" "$chip" "$dir"
    fi
  done
done

printf "__SECTION__\truntime_assets\n"
for path in \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/sentieon \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bundles/SentieonIlluminaWGS2.2.bundle \
  /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bundles/DNAscopeONT2.3.bundle; do
  if [[ -e "$path" ]]; then
    printf "__RUNTIME__\t%s\t%s\n" "$(stat -c '%s' "$path")" "$path"
  else
    printf "__RUNTIME_MISSING__\t%s\n" "$path"
  fi
done
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster", default="dyecX4")
    parser.add_argument("--profile", default="lsmc")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    target = resolve_headnode_instance_id(args.cluster, args.region, profile=args.profile)
    wait_for_ssm_online(target.instance_id, args.region, profile=args.profile, timeout=600)
    result = run_shell(
        target.instance_id,
        args.region,
        SCRIPT,
        profile=args.profile,
        timeout=180,
        comment="Verify full-depth 4NA SMN12 inputs",
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
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
