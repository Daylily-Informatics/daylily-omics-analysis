#!/usr/bin/env python3
"""Read-only dyecX4 inspection for NA00232 four-chip SMN12 validation."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


STAGED_ROOT = "/fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z"
RAW_ROOT = "/fsx/run_dir_mounts/20260513_ONT_HG003"
RUNTIME_ROOT = "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03"


def parse_counts(stdout: str) -> dict[str, dict[str, str]]:
    counts: dict[str, dict[str, str]] = {}
    for line in stdout.splitlines():
        if not line.startswith("__COUNT__\t"):
            continue
        _, kind, name, count, bytes_total, path = line.split("\t", 5)
        counts[f"{kind}:{name}"] = {
            "kind": kind,
            "name": name,
            "count": count,
            "bytes": bytes_total,
            "path": path,
        }
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster", default="dyecX4")
    parser.add_argument("--profile", default="lsmc")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    target = resolve_headnode_instance_id(args.cluster, args.region, profile=args.profile)
    wait_for_ssm_online(target.instance_id, args.region, profile=args.profile, timeout=600)

    remote_script = f"""
set -euo pipefail
printf "__META__\\tdate_utc\\t%s\\n" "$(date -u +%FT%TZ)"
printf "__META__\\thostname\\t%s\\n" "$(hostname)"
printf "__META__\\tuser\\t%s\\n" "$(id -un)"
printf "__META__\\tstaged_root\\t%s\\n" "{STAGED_ROOT}"
printf "__META__\\traw_root\\t%s\\n" "{RAW_ROOT}"
printf "__META__\\truntime_root\\t%s\\n" "{RUNTIME_ROOT}"

for f in \\
  "{STAGED_ROOT}/ilmn/4_nas_ds_to_20x/NA00232-SMN_S46_ds20x_R1_001.fastq.gz" \\
  "{STAGED_ROOT}/ilmn/4_nas_ds_to_20x/NA00232-SMN_S46_ds20x_R2_001.fastq.gz"; do
  if [[ -f "$f" ]]; then
    stat -Lc "__FILE__	ILMN	%n	%s	%Y" "$f"
  else
    printf "__MISSING__\\tILMN\\t%s\\n" "$f"
  fi
done

for chip in chip1 chip2 chip3 chip4; do
  dir="{STAGED_ROOT}/ont/$chip/fastq_pass/barcode18"
  if [[ -d "$dir" ]]; then
    count=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | wc -l | tr -d ' ')
    bytes=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' -printf '%s\\n' | awk '{{s+=$1}} END {{print s+0}}')
  else
    count=0
    bytes=0
  fi
  printf "__COUNT__\\tstaged\\t%s\\t%s\\t%s\\t%s\\n" "$chip" "$count" "$bytes" "$dir"
  first=""
  if [[ -d "$dir" ]]; then
    first=$(find "$dir" -maxdepth 1 -type f -name '*.fastq.gz' | sort | head -n 1)
  fi
  printf "__PATH_SAMPLE__\\tstaged\\t%s\\tfirst\\t%s\\n" "$chip" "$first"
done

if [[ -d "{RAW_ROOT}" ]]; then
  raw_count=$(find "{RAW_ROOT}" -type f -path '*/fastq_pass/barcode18/*.fastq.gz' | wc -l | tr -d ' ')
  raw_bytes=$(find "{RAW_ROOT}" -type f -path '*/fastq_pass/barcode18/*.fastq.gz' -printf '%s\\n' | awk '{{s+=$1}} END {{print s+0}}')
  printf "__COUNT__\\traw\\tbarcode18_all\\t%s\\t%s\\t%s\\n" "$raw_count" "$raw_bytes" "{RAW_ROOT}"
  raw_first=$(find "{RAW_ROOT}" -type f -path '*/fastq_pass/barcode18/*.fastq.gz' | sort | head -n 1)
  printf "__PATH_SAMPLE__\\traw\\tbarcode18_all\\tfirst\\t%s\\n" "$raw_first"
  for flowcell in PBM13545 PBM14931 PBM13048; do
    flow_count=$(find "{RAW_ROOT}" -type f -path "*/fastq_pass/barcode18/${{flowcell}}_pass_barcode18*.fastq.gz" | wc -l | tr -d ' ')
    flow_bytes=$(find "{RAW_ROOT}" -type f -path "*/fastq_pass/barcode18/${{flowcell}}_pass_barcode18*.fastq.gz" -printf '%s\\n' | awk '{{s+=$1}} END {{print s+0}}')
    flow_first=$(find "{RAW_ROOT}" -type f -path "*/fastq_pass/barcode18/${{flowcell}}_pass_barcode18*.fastq.gz" | sort | head -n 1)
    printf "__COUNT__\\traw\\t%s\\t%s\\t%s\\t%s\\n" "$flowcell" "$flow_count" "$flow_bytes" "{RAW_ROOT}"
    printf "__PATH_SAMPLE__\\traw\\t%s\\tfirst\\t%s\\n" "$flowcell" "$flow_first"
  done
else
  printf "__MISSING__\\tRAW_ROOT\\t%s\\n" "{RAW_ROOT}"
fi

for p in \\
  "{RUNTIME_ROOT}/bin/sentieon" \\
  "{RUNTIME_ROOT}/bin/sentieon-cli" \\
  "{RUNTIME_ROOT}/bin/segdup-caller" \\
  "{RUNTIME_ROOT}/bundles/SentieonIlluminaWGS2.2.bundle" \\
  "{RUNTIME_ROOT}/bundles/SentieonIlluminaWGS2.2.bundle/dnascope.model" \\
  "{RUNTIME_ROOT}/bundles/SentieonIlluminaWGS2.2.bundle/bwa.model" \\
  "{RUNTIME_ROOT}/bundles/DNAscopeONT2.3.bundle" \\
  "/fsx/references/runtime_assets/tool_specific_resources/hapsma/hg38_broad/SMN_region_38.smn_only.bed" \\
  "/fsx/references/runtime_assets/tool_specific_resources/hapsma/hg38_broad/hg38_broad_smn_100kb_pad_homopolymer_run3.bed" \\
  "/fsx/references/runtime_assets/tool_specific_resources/clair3/models/r1041_e82_400bps_sup_v500/pileup.pt" \\
  "/fsx/references/runtime_assets/tool_specific_resources/clair3/models/r1041_e82_400bps_sup_v500/full_alignment.pt" \\
  "/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.map-ont.mmi"; do
  if [[ -e "$p" ]]; then
    stat -Lc "__RUNTIME__	%n	%F	%s	%Y" "$p"
  else
    printf "__MISSING__\\tRUNTIME\\t%s\\n" "$p"
  fi
done

set +e
PATH="{RUNTIME_ROOT}/bin:$PATH" sentieon --version
printf "__VERSION_RC__\\tsentieon\\t%s\\n" "$?"
PATH="{RUNTIME_ROOT}/bin:$PATH" sentieon-cli --version
printf "__VERSION_RC__\\tsentieon-cli\\t%s\\n" "$?"
PATH="{RUNTIME_ROOT}/bin:$PATH" segdup-caller --version
printf "__VERSION_RC__\\tsegdup-caller\\t%s\\n" "$?"
set -e
"""

    result = run_shell(
        target.instance_id,
        args.region,
        remote_script,
        profile=args.profile,
        timeout=300,
        comment="Inspect NA00232 four-chip SMN12 inputs and Sentieon runtime",
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
        "counts": parse_counts(result.stdout),
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
