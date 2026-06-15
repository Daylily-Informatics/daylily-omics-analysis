#!/usr/bin/env python3
"""Collect compact full-depth SMN12 caller results."""

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


REMOTE_COLLECT = r'''
from __future__ import annotations

import csv
import json
import os
import re
from pathlib import Path

RUN_ID = "HYB-4NA-smn12-full-20260615"
EXPECTED = {
    "NA00232": {"SMN1": 0, "SMN2": 2},
    "NA09677": {"SMN1": 0, "SMN2": 3},
}


def rows_tsv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def read_json(path: Path) -> object:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def read_smaca(path: Path) -> dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    header = None
    values = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("# id|"):
            header = line[2:].split("|")
        elif line and not line.startswith("#"):
            values = line.split("|")
            break
    if not header or not values:
        return {}
    row = dict(zip(header, values))
    keep = [
        "avg_cov_SMN1",
        "avg_cov_SMN2",
        "cov_SMN1_a",
        "cov_SMN1_b",
        "cov_SMN1_c",
        "cov_SMN2_a",
        "cov_SMN2_b",
        "cov_SMN2_c",
        "Pi_a",
        "Pi_b",
        "Pi_c",
    ]
    return {key: row.get(key, "") for key in keep if key in row}


def read_smn12(path: Path) -> dict[str, object]:
    payload = read_json(path)
    if not isinstance(payload, dict) or not payload:
        return {}
    row = next(iter(payload.values()))
    if not isinstance(row, dict):
        return {}
    keep = ["SMN1", "SMN2", "SMN2delta78", "isSMA", "isCarrier", "Median_depth", "Total_CN_raw", "Full_length_CN_raw"]
    return {key: row.get(key) for key in keep if key in row}


def read_sma_finder(path: Path) -> dict[str, object]:
    payload = read_json(path)
    if not isinstance(payload, dict):
        return {}
    row = payload.get("result", {})
    if not isinstance(row, dict):
        return {}
    keep = ["sma_status", "confidence_score", "c840_total_reads", "c840_reads_with_smn1_base_C", "genome_version"]
    return {key: row.get(key) for key in keep if key in row}


def read_hapsma(path: Path) -> dict[str, str]:
    rows = rows_tsv(path)
    if not rows:
        return {}
    row = rows[0]
    keep = ["region_phase_status", "region_phase_reason", "bed_phase_status", "bed_phase_reason", "mean_smn_region_coverage", "ploidy"]
    return {key: row.get(key, "") for key in keep if key in row}


def read_segdup_yaml(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
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


def one(root: Path, pattern: str) -> Path | None:
    matches = sorted(p for p in root.glob(pattern) if p.is_file())
    return matches[0] if matches else None


base = Path("results/day/hg38_broad")
out: dict[str, object] = {
    "utc": os.popen("date -u +%FT%TZ").read().strip(),
    "repo": str(Path.cwd()),
    "run_id": RUN_ID,
    "samples": {},
    "reports": {},
}

for report in [
    base / "other_reports" / "htd_calls_mqc.tsv",
    base / "other_reports" / "smn12_orthogonal_calls_mqc.tsv",
]:
    compact = []
    for row in rows_tsv(report):
        sample = "NA00232" if "NA00232" in row.get("sample", "") else "NA09677" if "NA09677" in row.get("sample", "") else row.get("sample", "")
        compact.append({
            "sample": sample,
            "caller": row.get("caller", ""),
            "status": row.get("status", ""),
            "smn1_copy_number": row.get("smn1_copy_number", ""),
            "smn2_copy_number": row.get("smn2_copy_number", ""),
            "affected_status": row.get("affected_status", ""),
            "carrier_status": row.get("carrier_status", ""),
            "confidence": row.get("confidence", ""),
            "discordance_flag": row.get("discordance_flag", ""),
        })
    out["reports"][report.name] = compact

for sample_id, expected in EXPECTED.items():
    sample_dirs = sorted(p for p in base.iterdir() if p.is_dir() and p.name.startswith(RUN_ID) and sample_id in p.name)
    sample_out: dict[str, object] = {
        "expected": expected,
        "sample_dirs": [p.as_posix() for p in sample_dirs],
    }
    if sample_dirs:
        sample_dir = sample_dirs[0]
        paths = {
            "smn12": one(sample_dir, "align/*/na/htd/smn12/*.summary.json"),
            "smaca": one(sample_dir, "align/*/na/htd/smaca/*.summary.tsv"),
            "sma_finder": one(sample_dir, "align/*/na/htd/sma_finder/*.summary.json"),
            "hapsma": one(sample_dir, "align/*/na/htd/hapsma/*.summary.tsv"),
            "sentieon_segdup_smn1": one(sample_dir, "align/*/na/segdup/sentdhiomr/results/SMN1/*.SMN1.yaml"),
        }
        sample_out["paths"] = {key: path.as_posix() if path else "" for key, path in paths.items()}
        sample_out["smn12"] = read_smn12(paths["smn12"]) if paths["smn12"] else {}
        sample_out["smaca"] = read_smaca(paths["smaca"]) if paths["smaca"] else {}
        sample_out["sma_finder"] = read_sma_finder(paths["sma_finder"]) if paths["sma_finder"] else {}
        sample_out["hapsma"] = read_hapsma(paths["hapsma"]) if paths["hapsma"] else {}
        sample_out["sentieon_segdup_smn1"] = read_segdup_yaml(paths["sentieon_segdup_smn1"]) if paths["sentieon_segdup_smn1"] else {}
    out["samples"][sample_id] = sample_out

print(json.dumps(out, indent=2, sort_keys=True))
'''


def parse_json(stdout: str) -> dict[str, object] | None:
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
    encoded = base64.b64encode(REMOTE_COLLECT.encode("utf-8")).decode("ascii")
    script = f"""
set -euo pipefail
cd "{REMOTE_REPO}"
python3 -c "import base64; exec(base64.b64decode('{encoded}').decode('utf-8'))"
"""
    result = run_shell(
        target.instance_id,
        args.region,
        script,
        profile=args.profile,
        timeout=180,
        comment="Collect compact full-depth SMN12 results",
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
        "collection": parse_json(result.stdout),
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
