#!/usr/bin/env python3
"""Bounded read-only inventory for active work and 4NA full-depth inputs."""

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
tmux ls 2>&1 | grep -E 'hg003_pg_.*hg38|hg003_linear_hg38|smn12|sentup_hiomr_recovery|sentup_hg003_hiomr_kitchensink_20260612T185650Z' | sed 's/^/__TMUX_RELEVANT__\t/' || true
tmux list-panes -a -F '__PANE__	#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}	#{pane_pid}	#{pane_current_command}' 2>/dev/null | grep -E 'hg003_pg_.*hg38|hg003_linear_hg38|smn12|sentup_hiomr_recovery|sentup_hg003_hiomr_kitchensink_20260612T185650Z' || true
squeue -u ubuntu -o '__SQUEUE__	%i	%T	%j	%M	%l	%D	%R' 2>&1 || true
ps -eo pid,ppid,stat,etime,args \
  | grep -E 'dy-r|day_run|snakemake|dyec export|fsx_export|data-repository|sentieon|segdup-caller|rtg|vcfeval|dnascope|sentdhiomr|sentpg|dayoa_' \
  | grep -v grep \
  | sed 's/^/__PROC__\t/' || true

printf "__SECTION__\tknown_sentieon_dirs\n"
{
  find /fsx/analysis_results/ubuntu -maxdepth 1 -mindepth 1 -type d \( \
    -name 'sentup_*' -o \
    -name 'hg003_ilmn30x_pg_*' -o \
    -name 'hg003_ilmn30x_linear_sentd_*' -o \
    -name 'hiomr_smn12_*' -o \
    -name 'pg_ilmn_hg002_hg003_*' -o \
    -name 'pg_ultima_hg003_*' -o \
    -name 'ont_hg003_5x_*' -o \
    -name 'ilmn_hg002_hg003_*' \
  \) -print 2>/dev/null
  find /fsx/analysis_results/dyecX4 -maxdepth 1 -mindepth 1 -type d \( \
    -name 'hg003_*' -o \
    -name 'na00232_smn12_*' \
  \) -print 2>/dev/null
} | sort | while read -r dir; do
  repo="$dir/daylily-omics-analysis"
  if [[ ! -d "$dir" ]]; then
    printf "__KNOWN_MISSING__\t%s\n" "$dir"
    continue
  fi
  size=not_collected
  latest_log=""
  success=no
  failure_hint=no
  if [[ -d "$repo/.snakemake/log" ]]; then
    latest_log=$(find "$repo/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
    if [[ -n "$latest_log" ]] && grep -q 'WORKFLOW SUCCESS' "$latest_log"; then
      success=yes
    fi
    if [[ -n "$latest_log" ]] && grep -Eq 'Error|Exception|WorkflowError|FAILED|RETURN CODE: [1-9]' "$latest_log"; then
      failure_hint=yes
    fi
  fi
  receipts=$(find "$dir" -name 'fsx_export.yaml' -type f 2>/dev/null | wc -l | tr -d ' ')
  printf "__KNOWN_DIR__\t%s\t%s\t%s\t%s\t%s\t%s\n" "$dir" "$size" "$success" "$failure_hint" "$receipts" "$latest_log"
done

printf "__SECTION__\t4na_ilmn_roots\n"
for root in /fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ilmn /fsx/analysis_results/ubuntu/4_nas_ds_to_20x_realcopy; do
  if [[ -d "$root" ]]; then
    find "$root" -maxdepth 3 -type d -printf "__ILMN_DIR__	%p\n" | sort | sed -n '1,80p'
  else
    printf "__ILMN_ROOT_MISSING__\t%s\n" "$root"
  fi
done

printf "__SECTION__\t4na_ilmn_fastqs\n"
for sample in NA00232 NA09677; do
  find /fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ilmn /fsx/analysis_results/ubuntu/4_nas_ds_to_20x_realcopy \
    -maxdepth 6 -type f -name "${sample}*.fastq.gz" -printf "__ILMN_FASTQ__	%s	%p\n" 2>/dev/null | sort
done

printf "__SECTION__\t4na_ont_fastqs\n"
for sample_barcode in barcode18 barcode19; do
  for chip in chip1 chip2 chip3 chip4; do
    dir="/fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ont/${chip}/fastq_pass/${sample_barcode}"
    if [[ -d "$dir" ]]; then
      count=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | wc -l | tr -d ' ')
      bytes=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
      first=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | sort | head -n 1)
      printf "__ONT_FASTQS__\t%s\t%s\t%s\t%s\t%s\t%s\n" "$sample_barcode" "$chip" "$count" "$bytes" "$dir" "$first"
    else
      printf "__ONT_MISSING__\t%s\t%s\t%s\n" "$sample_barcode" "$chip" "$dir"
    fi
  done
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
        timeout=300,
        comment="Bounded active work and full-depth 4NA input inventory",
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
