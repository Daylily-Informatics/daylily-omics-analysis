#!/usr/bin/env python3
"""Summarize SMN12 orthogonal caller outputs for MultiQC custom content."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


HTD_RE = re.compile(
    r"(?P<sample>[^/]+)/align/(?P<aligner>[^/]+)/(?P<deduper>[^/]+)/htd/(?P<caller>[^/]+)/"
)
SEGDUP_RE = re.compile(
    r"(?P<sample>[^/]+)/align/(?P<aligner>[^/]+)/(?P<deduper>[^/]+)/segdup/sentdhiomr/"
)

CALLER_CLASS = {
    "smn12": "copy_number",
    "smaca": "copy_number",
    "sma_finder": "affected_status_only",
    "hapsma": "long_read_haplotype_dev",
    "sentieon_segdup_smn1": "hybrid_segdup",
}

EVIDENCE_SOURCE = {
    "smn12": "short_read_cram",
    "smaca": "short_read_cram",
    "sma_finder": "short_read_cram",
    "hapsma": "ONT_long_read_cram",
    "sentieon_segdup_smn1": "HiOMR_SR_LR",
}

FIELDS = [
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
    "primary_path",
    "output_paths",
]


def _read_first_tsv(path: Path) -> dict[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return next(reader, {}) or {}


def _read_tsv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return list(reader)


def _read_json(path: Path) -> Any:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _find_value(payload: Any, keys: set[str]) -> str:
    if isinstance(payload, dict):
        for key, value in payload.items():
            if str(key).lower() in keys and value not in [None, ""]:
                return str(value)
        for value in payload.values():
            found = _find_value(value, keys)
            if found != "NA":
                return found
    elif isinstance(payload, list):
        for value in payload:
            found = _find_value(value, keys)
            if found != "NA":
                return found
    return "NA"


def _normal_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value).lower())


def _filled(value: object) -> bool:
    return str(value or "").strip() not in {"", "NA", "na", "None", "none", "."}


def _extract_copy_number(rows: list[dict[str, str]], gene: str) -> str:
    gene_key = gene.lower()
    copy_tokens = ("copynumber", "copy", "cn", "dosage", "exon7", "exon8")
    gene_column_keys = {"gene", "target", "locus", "region", "name"}
    value_column_tokens = ("copynumber", "copy", "cn", "dosage", "value")

    for row in rows:
        for key, value in row.items():
            normal_key = _normal_key(key)
            if (
                gene_key in normal_key
                and _filled(value)
                and (normal_key == gene_key or any(token in normal_key for token in copy_tokens))
            ):
                return str(value)

    for row in rows:
        row_gene = ""
        for key, value in row.items():
            if _normal_key(key) in gene_column_keys:
                row_gene = _normal_key(value)
                break
        if gene_key not in row_gene:
            continue
        for key, value in row.items():
            normal_key = _normal_key(key)
            if _filled(value) and any(token in normal_key for token in value_column_tokens):
                return str(value)
    return "NA"


def _path_for(paths: list[Path], suffix: str) -> Path | None:
    for path in paths:
        if path.name.endswith(suffix):
            return path
    return None


def _json_path(paths: list[Path]) -> Path | None:
    for path in paths:
        if path.name.endswith(".json"):
            return path
    return None


def _tsv_path(paths: list[Path]) -> Path | None:
    for path in paths:
        if path.name.endswith(".tsv"):
            return path
    return None


def _status(paths: list[Path]) -> str:
    if any(path.name.endswith(".done") and path.exists() for path in paths):
        return "complete"
    if any(path.exists() for path in paths):
        return "partial"
    return "missing"


def _base_row(sample: str, aligner: str, deduper: str, caller: str, paths: list[Path]) -> dict[str, str]:
    primary = _tsv_path(paths) or _json_path(paths) or _path_for(paths, ".yaml") or paths[0]
    return {
        "sample": sample,
        "aligner": aligner,
        "deduper": deduper,
        "caller": caller,
        "gene": "SMN1/SMN2" if caller != "sentieon_segdup_smn1" else "SMN1",
        "caller_class": CALLER_CLASS.get(caller, "unknown"),
        "evidence_source": EVIDENCE_SOURCE.get(caller, "NA"),
        "smn1_copy_number": "NA",
        "smn2_copy_number": "NA",
        "affected_status": "NA",
        "carrier_status": "NA",
        "confidence": "NA",
        "status": _status(paths),
        "discordance_flag": "not_evaluated",
        "primary_path": str(primary),
        "output_paths": json.dumps([str(path) for path in sorted(paths)]),
    }


def _smn12_row(row: dict[str, str], paths: list[Path]) -> dict[str, str]:
    payload = _read_json(_json_path(paths) or Path("NA"))
    row["smn1_copy_number"] = _find_value(payload, {"smn1_cn", "smn1_copy_number", "smn1"})
    row["smn2_copy_number"] = _find_value(payload, {"smn2_cn", "smn2_copy_number", "smn2"})
    row["affected_status"] = _find_value(payload, {"issma", "is_sma", "affected_status"})
    row["carrier_status"] = _find_value(payload, {"iscarrier", "is_carrier", "carrier_status"})
    row["confidence"] = _find_value(payload, {"confidence", "quality", "filter"})
    return row


def _smaca_row(row: dict[str, str], paths: list[Path]) -> dict[str, str]:
    data = _read_tsv_rows(_tsv_path(paths) or Path("NA"))
    row["smn1_copy_number"] = _extract_copy_number(data, "smn1")
    row["smn2_copy_number"] = _extract_copy_number(data, "smn2")
    return row


def _sma_finder_row(row: dict[str, str], paths: list[Path]) -> dict[str, str]:
    data = _read_first_tsv(_tsv_path(paths) or Path("NA"))
    row["affected_status"] = data.get("sma_status", "NA") or "NA"
    row["carrier_status"] = "not_reported"
    row["confidence"] = data.get("confidence_score", "NA") or "NA"
    return row


def _hapsma_row(row: dict[str, str], paths: list[Path]) -> dict[str, str]:
    data = _read_first_tsv(_tsv_path(paths) or Path("NA"))
    row["affected_status"] = "not_reported"
    row["carrier_status"] = "not_reported"
    row["confidence"] = data.get("mean_smn_region_coverage", "NA") or "NA"
    return row


def _segdup_row(row: dict[str, str], paths: list[Path]) -> dict[str, str]:
    yaml_path = _path_for(paths, ".yaml")
    row["primary_path"] = str(yaml_path or row["primary_path"])
    row["affected_status"] = "not_reported"
    row["carrier_status"] = "not_reported"
    return row


def _caller_row(sample: str, aligner: str, deduper: str, caller: str, paths: list[Path]) -> dict[str, str]:
    row = _base_row(sample, aligner, deduper, caller, paths)
    if caller == "smn12":
        return _smn12_row(row, paths)
    if caller == "smaca":
        return _smaca_row(row, paths)
    if caller == "sma_finder":
        return _sma_finder_row(row, paths)
    if caller == "hapsma":
        return _hapsma_row(row, paths)
    if caller == "sentieon_segdup_smn1":
        return _segdup_row(row, paths)
    return row


def _with_discordance(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    by_sample: dict[tuple[str, str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_sample[(row["sample"], row["aligner"], row["deduper"])].append(row)
    for group in by_sample.values():
        cn_pairs = {
            (row["smn1_copy_number"], row["smn2_copy_number"])
            for row in group
            if row["smn1_copy_number"] != "NA" or row["smn2_copy_number"] != "NA"
        }
        affected = {
            row["affected_status"]
            for row in group
            if row["affected_status"] not in {"NA", "not_reported"}
        }
        flag = "discordant" if len(cn_pairs) > 1 or len(affected) > 1 else "no_discordance_detected"
        if not cn_pairs and not affected:
            flag = "not_evaluated"
        for row in group:
            row["discordance_flag"] = flag
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    groups: dict[tuple[str, str, str, str], list[Path]] = defaultdict(list)
    for raw_path in args.paths:
        htd = HTD_RE.search(raw_path)
        if htd:
            groups[
                (
                    htd.group("sample"),
                    htd.group("aligner"),
                    htd.group("deduper"),
                    htd.group("caller"),
                )
            ].append(Path(raw_path))
            continue
        segdup = SEGDUP_RE.search(raw_path)
        if segdup and "SMN1" in raw_path:
            groups[
                (
                    segdup.group("sample"),
                    segdup.group("aligner"),
                    segdup.group("deduper"),
                    "sentieon_segdup_smn1",
                )
            ].append(Path(raw_path))

    rows = [
        _caller_row(sample, aligner, deduper, caller, sorted(paths))
        for (sample, aligner, deduper, caller), paths in sorted(groups.items())
    ]
    rows = _with_discordance(rows)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
