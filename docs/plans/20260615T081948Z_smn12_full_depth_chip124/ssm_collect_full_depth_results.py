#!/usr/bin/env python3
"""Collect full-depth two-sample SMN12 caller outputs from the dyecX4 workdir."""

from __future__ import annotations

import argparse
import base64
import json
from datetime import datetime, timezone
from pathlib import Path

from daylily_ec.aws.ssm import resolve_headnode_instance_id, run_shell, wait_for_ssm_online


REMOTE_REPO = (
    "/fsx/analysis_results/dyecX4/"
    "smn12_full_ilmn_chip124_20260615T092300Z/daylily-omics-analysis"
)


COLLECT_PY = r'''
from __future__ import annotations

import csv
import json
import os
import re
from pathlib import Path

RUN_ID = "HYB-4NA-smn12-full-20260615"
SAMPLES = {
    "NA00232": {"expected_smn1": 0, "expected_smn2": 2},
    "NA09677": {"expected_smn1": 0, "expected_smn2": 3},
}


def stat_payload(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"exists": False}
    st = path.stat()
    return {"exists": True, "size": st.st_size, "mtime": int(st.st_mtime)}


def read_tsv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def read_json(path: Path) -> object:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def compact_report_rows(path: Path) -> list[dict[str, str]]:
    keep = [
        "sample",
        "Sample",
        "sample_id",
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
        "metric",
        "value",
    ]
    rows = []
    for row in read_tsv_rows(path):
        rows.append({key: row.get(key, "") for key in keep if key in row})
    return rows


def read_smaca(path: Path) -> dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
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
    return dict(zip(header.split("|"), values.split("|")))


def read_smn12(path: Path) -> dict[str, object]:
    payload = read_json(path)
    if not isinstance(payload, dict) or not payload:
        return {}
    row = next(iter(payload.values()))
    if not isinstance(row, dict):
        return {}
    keep = [
        "SMN1",
        "SMN2",
        "SMN2delta78",
        "isSMA",
        "isCarrier",
        "Info",
        "Median_depth",
        "Total_CN_raw",
        "Full_length_CN_raw",
    ]
    return {key: row.get(key) for key in keep}


def read_sma_finder(path: Path) -> dict[str, object]:
    payload = read_json(path)
    if not isinstance(payload, dict):
        return {}
    row = payload.get("result", {})
    if not isinstance(row, dict):
        return {}
    return dict(row)


def read_hapsma(path: Path) -> dict[str, str]:
    rows = read_tsv_rows(path)
    if not rows:
        return {}
    return rows[0]


def read_segdup_yaml(path: Path) -> dict[str, object]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    out: dict[str, object] = {}
    for key in ["SMN1", "SMN2"]:
        match = re.search(rf"^[ ]{{4}}{key}:\s+(-?\d+)", text, re.MULTILINE)
        if match:
            out[key] = int(match.group(1))
    for key in ["segdup-caller", "sentieon"]:
        match = re.search(rf"^[ ]{{4}}{re.escape(key)}:\s+'?([^'\n]+)'?", text, re.MULTILINE)
        if match:
            out[key.replace("-", "_")] = match.group(1).strip()
    return out


def first_match(root: Path, pattern: str) -> Path | None:
    matches = sorted(path for path in root.glob(pattern) if path.is_file())
    return matches[0] if matches else None


def add_files(files: dict[str, dict[str, object]], root: Path, patterns: list[str]) -> None:
    for pattern in patterns:
        for path in sorted(root.glob(pattern)):
            if path.is_file():
                files[path.as_posix()] = stat_payload(path)


base = Path("results/day/hg38_broad")
sample_dirs = sorted(path for path in base.iterdir() if path.is_dir() and path.name.startswith(RUN_ID))
files: dict[str, dict[str, object]] = {}
reports: dict[str, list[dict[str, str]]] = {}
summaries: dict[str, object] = {}

for rel in [
    "results/day/hg38_broad/other_reports/smn12_orthogonal_calls_mqc.tsv",
    "results/day/hg38_broad/other_reports/htd_calls_mqc.tsv",
]:
    path = Path(rel)
    files[rel] = stat_payload(path)
    reports[path.name] = compact_report_rows(path)

for sample_id, expected in SAMPLES.items():
    dirs = [path for path in sample_dirs if sample_id in path.name]
    sample_summary: dict[str, object] = {"expected": expected, "sample_dirs": [path.as_posix() for path in dirs]}
    for sample_dir in dirs:
        smn12 = first_match(sample_dir, "align/*/na/htd/smn12/*.summary.json")
        smaca = first_match(sample_dir, "align/*/na/htd/smaca/*.summary.tsv")
        sma_finder = first_match(sample_dir, "align/*/na/htd/sma_finder/*.summary.json")
        hapsma = first_match(sample_dir, "align/*/na/htd/hapsma/*.summary.tsv")
        segdup = first_match(sample_dir, "align/*/na/segdup/sentdhiomr/results/SMN1/*.SMN1.yaml")
        sample_summary.update(
            {
                "smn12": read_smn12(smn12) if smn12 else {},
                "smaca": read_smaca(smaca) if smaca else {},
                "sma_finder": read_sma_finder(sma_finder) if sma_finder else {},
                "hapsma": read_hapsma(hapsma) if hapsma else {},
                "sentieon_segdup_smn1": read_segdup_yaml(segdup) if segdup else {},
            }
        )
        for candidate in [smn12, smaca, sma_finder, hapsma, segdup]:
            if candidate:
                files[candidate.as_posix()] = stat_payload(candidate)
        add_files(
            files,
            sample_dir,
            [
                "align/*/na/htd/smn12/*",
                "align/*/na/htd/smaca/*",
                "align/*/na/htd/sma_finder/*",
                "align/*/na/htd/hapsma/*.summary.tsv",
                "align/*/na/htd/hapsma/*.done",
                "align/*/na/segdup/sentdhiomr/results/SMN1/*",
                "align/*/na/segdup/sentdhiomr/log/*SMN1*",
            ],
        )
    summaries[sample_id] = sample_summary

print(
    json.dumps(
        {
            "utc": os.popen("date -u +%FT%TZ").read().strip(),
            "repo": str(Path.cwd()),
            "run_id": RUN_ID,
            "sample_dirs": [path.as_posix() for path in sample_dirs],
            "reports": reports,
            "summaries": summaries,
            "files": files,
        },
        indent=2,
        sort_keys=True,
    )
)
'''


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
    collect_b64 = base64.b64encode(COLLECT_PY.encode("utf-8")).decode("ascii")
    script = f"""
set -euo pipefail
cd "{REMOTE_REPO}"
python3 -c "import base64; exec(base64.b64decode('{collect_b64}').decode('utf-8'))"
"""
    result = run_shell(
        target.instance_id,
        args.region,
        script,
        profile=args.profile,
        timeout=180,
        comment="Collect full-depth SMN12 chip124 results",
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
