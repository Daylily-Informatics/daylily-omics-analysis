#!/usr/bin/env python3
"""Collect NA00232 chip124 SMN12 caller outputs from the dyecX4 workdir."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


REMOTE_REPO = "/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/daylily-omics-analysis"


def parse_collection(stdout: str) -> dict[str, object] | None:
    start = stdout.find("{")
    end = stdout.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        return json.loads(stdout[start : end + 1])
    except json.JSONDecodeError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster", default="dyecX4")
    parser.add_argument("--profile", default="lsmc")
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    target = resolve_headnode_instance_id(args.cluster, args.region, profile=args.profile)
    wait_for_ssm_online(target.instance_id, args.region, profile=args.profile, timeout=300)

    script = """
set -euo pipefail
cd "__REMOTE_REPO__"
python3 - <<'PY'
from __future__ import annotations

import gzip
import json
import os
import re
from pathlib import Path


def stat_payload(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"exists": False}
    st = path.stat()
    return {"exists": True, "size": st.st_size, "mtime": int(st.st_mtime)}


def read_tsv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        import csv
        return list(csv.DictReader(handle, delimiter="\\t"))


def read_json(path: Path) -> object:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def compact_report_rows(path: Path) -> list[dict[str, str]]:
    keep = [
        "sample",
        "aligner",
        "deduper",
        "caller",
        "gene",
        "caller_class",
        "evidence_source",
        "smn1_copy_number",
        "smn2_copy_number",
        "affected_status",
        "carrier_status",
        "confidence",
        "status",
        "discordance_flag",
    ]
    return [{key: row.get(key, "") for key in keep if key in row} for row in read_tsv_rows(path)]


def read_smaca(path: Path) -> dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    lines = [line.rstrip("\\n") for line in path.read_text(encoding="utf-8", errors="replace").splitlines()]
    header = ""
    values = ""
    for line in lines:
        if line.startswith("# id|"):
            header = line[2:]
        elif line and not line.startswith("#"):
            values = line
            break
    if not header or not values:
        return {}
    keys = header.split("|")
    vals = values.split("|")
    row = dict(zip(keys, vals))
    return {
        "avg_cov_SMN1": row.get("avg_cov_SMN1", ""),
        "avg_cov_SMN2": row.get("avg_cov_SMN2", ""),
        "cov_SMN1_a": row.get("cov_SMN1_a", ""),
        "cov_SMN2_a": row.get("cov_SMN2_a", ""),
        "g.27134T>G": row.get("g.27134T>G", ""),
    }


def read_smn12(path: Path) -> dict[str, object]:
    payload = read_json(path)
    if not isinstance(payload, dict) or not payload:
        return {}
    row = next(iter(payload.values()))
    if not isinstance(row, dict):
        return {}
    return {
        "SMN1": row.get("SMN1"),
        "SMN2": row.get("SMN2"),
        "SMN2delta78": row.get("SMN2delta78"),
        "isSMA": row.get("isSMA"),
        "isCarrier": row.get("isCarrier"),
        "Info": row.get("Info"),
        "Median_depth": row.get("Median_depth"),
        "Total_CN_raw": row.get("Total_CN_raw"),
        "Full_length_CN_raw": row.get("Full_length_CN_raw"),
    }


def read_sma_finder(path: Path) -> dict[str, object]:
    payload = read_json(path)
    if not isinstance(payload, dict):
        return {}
    row = payload.get("result", {})
    if not isinstance(row, dict):
        return {}
    return {
        "sma_status": row.get("sma_status"),
        "confidence_score": row.get("confidence_score"),
        "c840_reads_with_smn1_base_C": row.get("c840_reads_with_smn1_base_C"),
        "c840_total_reads": row.get("c840_total_reads"),
    }


def read_hapsma(path: Path) -> dict[str, str]:
    rows = read_tsv_rows(path)
    if not rows:
        return {}
    row = rows[0]
    return {
        "mean_smn_region_coverage": row.get("mean_smn_region_coverage", ""),
        "bed_phase_set": row.get("bed_phase_set", ""),
        "bed_phase_status": row.get("bed_phase_status", ""),
        "region_phase_set": row.get("region_phase_set", ""),
        "region_phase_status": row.get("region_phase_status", ""),
    }


def read_segdup_yaml(path: Path) -> dict[str, object]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    out: dict[str, object] = {}
    for key in ["SMN1", "SMN2"]:
        match = re.search(rf"^[ ]{{4}}{key}:\\s+(-?\\d+)", text, re.MULTILINE)
        if match:
            out[key] = int(match.group(1))
    for key in ["segdup-caller", "sentieon"]:
        match = re.search(rf"^[ ]{{4}}{re.escape(key)}:\\s+'?([^'\\n]+)'?", text, re.MULTILINE)
        if match:
            out[key.replace("-", "_")] = match.group(1).strip()
    return out


def add_file(files: dict[str, dict[str, object]], path: Path) -> None:
    rel = path.as_posix()
    files[rel] = stat_payload(path)


base = Path("results/day/hg38_broad")
sample_dirs = sorted(p for p in base.glob("HYB-NA00232-smn12-current-20260615-*") if p.is_dir())
files: dict[str, dict[str, object]] = {}
reports: dict[str, list[dict[str, str]]] = {}
summaries: dict[str, object] = {}

for rel in [
    "results/day/hg38_broad/other_reports/smn12_orthogonal_calls_mqc.tsv",
    "results/day/hg38_broad/other_reports/htd_calls_mqc.tsv",
]:
    path = Path(rel)
    add_file(files, path)
    reports[path.name] = compact_report_rows(path)

for sample_dir in sample_dirs:
    sample = sample_dir.name
    summaries["smn12"] = read_smn12(sample_dir / f"align/sentmm2ont/na/htd/smn12/{sample}.sentmm2ont.na.smn12.summary.json")
    summaries["sma_finder"] = read_sma_finder(sample_dir / f"align/sentmm2ont/na/htd/sma_finder/{sample}.sentmm2ont.na.sma_finder.summary.json")
    summaries["smaca"] = read_smaca(sample_dir / f"align/sentmm2ont/na/htd/smaca/{sample}.sentmm2ont.na.smaca.summary.tsv")
    summaries["hapsma"] = read_hapsma(sample_dir / f"align/sentmm2ont/na/htd/hapsma/{sample}.sentmm2ont.na.hapsma.summary.tsv")
    summaries["sentieon_segdup_smn1"] = read_segdup_yaml(sample_dir / f"align/sentmm2ont/na/segdup/sentdhiomr/results/SMN1/{sample}.SMN1.yaml")
    for pattern in [
        "align/sentmm2ont/na/htd/smn12/*",
        "align/sentmm2ont/na/htd/smaca/*",
        "align/sentmm2ont/na/htd/sma_finder/*",
        "align/sentmm2ont/na/htd/hapsma/*.summary.tsv",
        "align/sentmm2ont/na/htd/hapsma/*.done",
        "align/sentmm2ont/na/segdup/sentdhiomr/results/SMN1/*",
        "align/sentmm2ont/na/segdup/sentdhiomr/log/*SMN1*",
        "logs/*sentdhiomr*",
    ]:
        for path in sorted(sample_dir.glob(pattern)):
            if path.is_file():
                add_file(files, path)

print(json.dumps(
    {
        "utc": os.popen("date -u +%FT%TZ").read().strip(),
        "repo": str(Path.cwd()),
        "sample_dirs": [p.as_posix() for p in sample_dirs],
        "reports": reports,
        "summaries": summaries,
        "files": files,
    },
    indent=2,
    sort_keys=True,
))
PY
""".replace("__REMOTE_REPO__", REMOTE_REPO)

    result = run_shell(
        target.instance_id,
        args.region,
        script,
        profile=args.profile,
        timeout=180,
        comment="Collect NA00232 chip124 SMN12 results",
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
        "remote_repo": REMOTE_REPO,
        "collection": parse_collection(result.stdout),
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
