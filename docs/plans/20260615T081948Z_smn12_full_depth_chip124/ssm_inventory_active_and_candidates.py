#!/usr/bin/env python3
"""Read-only inventory for active DYEC work and completed Sentieon candidates."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


SCRIPT = r'''
set -euo pipefail
printf "__META__\tutc\t%s\n" "$(date -u +%FT%TZ)"
printf "__META__\thostname\t%s\n" "$(hostname)"
printf "__META__\tuser\t%s\n" "$(id -un)"
printf "__META__\tpwd\t%s\n" "$PWD"

printf "__SECTION__\tcommands\n"
for cmd in tmux squeue ps find awk sed grep sort tail head du git aws python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "__CMD__\t%s\t%s\n" "$cmd" "$(command -v "$cmd")"
  else
    printf "__CMD_MISSING__\t%s\n" "$cmd"
  fi
done

printf "__SECTION__\ttmux_sessions\n"
tmux ls 2>&1 | sed 's/^/__TMUX__\t/' || true

printf "__SECTION__\ttmux_panes\n"
tmux list-panes -a -F '__PANE__	#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}	#{pane_pid}	#{pane_current_command}' 2>/dev/null || true

printf "__SECTION__\tslurm_jobs\n"
squeue -u ubuntu -o '__SQUEUE__	%i	%T	%j	%M	%l	%D	%R' 2>&1 || true

printf "__SECTION__\tactive_processes\n"
ps -eo pid,ppid,stat,etime,args \
  | grep -E 'dy-r|day_run|snakemake|dyec export|fsx_export|data-repository|sentieon|segdup-caller|rtg|vcfeval|dnascope|sentdhiomr|sentpg|dayoa_' \
  | grep -v grep \
  | sed 's/^/__PROC__\t/' || true

printf "__SECTION__\tactive_export_tasks\n"
aws fsx describe-data-repository-tasks \
  --query 'DataRepositoryTasks[?Lifecycle!=`SUCCEEDED` && Lifecycle!=`FAILED` && Lifecycle!=`CANCELED`].[TaskId,Lifecycle,Type,CreationTime,FileSystemId,Paths]' \
  --output json 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); [print("__FSX_TASK__\t" + json.dumps(x, default=str)) for x in data]' || true

printf "__SECTION__\tanalysis_dirs\n"
for base in /fsx/analysis_results/ubuntu /fsx/analysis_results/dyecX4; do
  if [[ ! -d "$base" ]]; then
    printf "__BASE_MISSING__\t%s\n" "$base"
    continue
  fi
  find "$base" -maxdepth 1 -mindepth 1 -type d | sort | while read -r dir; do
    name=$(basename "$dir")
    repo="$dir/daylily-omics-analysis"
    mtime=$(stat -Lc '%Y' "$dir" 2>/dev/null || echo 0)
    size=$(du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0)
    has_repo=no
    has_results=no
    success=no
    has_failure=no
    sentieon_hint=no
    latest_log=
    latest_log_tail=
    export_receipts=0
    if [[ -d "$repo/.git" ]]; then
      has_repo=yes
    fi
    if [[ -d "$repo/results/day" ]]; then
      has_results=yes
    fi
    if [[ -d "$repo/.snakemake/log" ]]; then
      latest_log=$(find "$repo/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
      if [[ -n "$latest_log" ]]; then
        if grep -q 'WORKFLOW SUCCESS' "$latest_log"; then
          success=yes
        fi
        if grep -Eq 'Error|Exception|WorkflowError|FAILED|RETURN CODE: [1-9]' "$latest_log"; then
          has_failure=yes
        fi
        latest_log_tail=$(tail -n 20 "$latest_log" | tr '\n' ' ' | tr '\t' ' ' | cut -c1-1000)
      fi
    fi
    if [[ -d "$repo/results/day" ]] && find "$repo/results/day" -maxdepth 8 -type f \( -path '*sent*' -o -path '*segdup*' -o -path '*pangenome*' \) -print -quit 2>/dev/null | grep -q .; then
      sentieon_hint=yes
    elif [[ -d "$repo/config" ]] && grep -RIl -m1 -E 'sentieon|sentd|sentpg|segdup|DNAscope|Pangenome' "$repo/config" "$repo/workflow" 2>/dev/null | head -n 1 | grep -q .; then
      sentieon_hint=yes
    fi
    export_receipts=$(find "$dir" -name 'fsx_export.yaml' -type f 2>/dev/null | wc -l | tr -d ' ')
    printf "__DIR__\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$base" "$name" "$dir" "$mtime" "$size" "$has_repo" "$has_results" "$success" "$has_failure" "$sentieon_hint" "$export_receipts" "$latest_log"
    if [[ -n "$latest_log_tail" ]]; then
      printf "__DIR_LOG_TAIL__\t%s\t%s\n" "$dir" "$latest_log_tail"
    fi
  done
done

printf "__SECTION__\tinput_roots\n"
for root in /fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z /fsx/analysis_results/ubuntu/4_nas_ds_to_20x_realcopy /fsx/data /fsx/control_data; do
  if [[ -e "$root" ]]; then
    stat -Lc "__INPUT_ROOT__	%n	%F	%s	%Y" "$root"
  else
    printf "__INPUT_ROOT_MISSING__\t%s\n" "$root"
  fi
done

printf "__SECTION__\tfull_depth_ilmn_candidates\n"
for sample in NA00232 NA09677; do
  find /fsx/analysis_inputs /fsx/analysis_results /fsx/data /fsx/control_data \
    \( -path /fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z -o -path /fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z \) -prune -o \
    -type f \( -name "${sample}*_R1*.fastq.gz" -o -name "${sample}*_R2*.fastq.gz" -o -name "*${sample}*.fastq.gz" \) \
    -printf "__ILMN_CAND__	%s	%p\n" 2>/dev/null \
    | sort | head -n 80
done

printf "__SECTION__\tont_chip_candidates\n"
for sample_barcode in barcode18 barcode19; do
  for chip in chip1 chip2 chip4; do
    dir="/fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ont/${chip}/fastq_pass/${sample_barcode}"
    if [[ -d "$dir" ]]; then
      count=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | wc -l | tr -d ' ')
      bytes=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
      first=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | sort | head -n 1)
      printf "__ONT_CAND__\t%s\t%s\t%s\t%s\t%s\t%s\n" "$sample_barcode" "$chip" "$count" "$bytes" "$dir" "$first"
    else
      printf "__ONT_MISSING__\t%s\t%s\t%s\n" "$sample_barcode" "$chip" "$dir"
    fi
  done
done
'''


def parse_dirs(stdout: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in stdout.splitlines():
        if not line.startswith("__DIR__\t"):
            continue
        parts = line.split("\t")
        if len(parts) < 13:
            continue
        rows.append(
            {
                "base": parts[1],
                "name": parts[2],
                "path": parts[3],
                "mtime_epoch": parts[4],
                "size_bytes": parts[5],
                "has_repo": parts[6],
                "has_results": parts[7],
                "workflow_success": parts[8],
                "has_failure_hint": parts[9],
                "sentieon_hint": parts[10],
                "export_receipts": parts[11],
                "latest_log": parts[12],
            }
        )
    return rows


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
        timeout=1200,
        comment="Inventory active work and Sentieon export candidates",
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
        "dirs": parse_dirs(result.stdout),
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
