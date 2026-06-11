#!/usr/bin/env python3
"""Summarize selected HTD caller outputs for MultiQC custom content."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path


HTD_RE = re.compile(
    r"(?P<sample>[^/]+)/align/(?P<aligner>[^/]+)/(?P<deduper>[^/]+)/htd/(?P<caller>[^/]+)/"
)

GENES = {
    "gauchian": "GBA",
    "cyrius": "CYP2D6",
    "smn12": "SMN1/SMN2",
    "parascopy": "MULTI",
    "smaca": "SMN1/SMN2",
    "sma_finder": "SMN1/SMN2",
    "hapsma": "SMN1/SMN2",
    "genetocn": "MULTI",
}

CALLER_CLASS = {
    "gauchian": "copy_number",
    "cyrius": "copy_number",
    "smn12": "copy_number",
    "smaca": "copy_number",
    "sma_finder": "affected_status_only",
    "hapsma": "long_read_haplotype_dev",
}

EVIDENCE_SOURCE = {
    "gauchian": "short_read_cram",
    "cyrius": "short_read_cram",
    "smn12": "short_read_cram",
    "smaca": "short_read_cram",
    "sma_finder": "short_read_cram",
    "hapsma": "ONT_long_read_cram",
}


def _read_cyrius_tsv(path: Path) -> tuple[str, str]:
    if not path.exists() or path.stat().st_size == 0:
        return "NA", "missing_tsv"
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        row = next(reader, None)
    if not row:
        return "NA", "empty_tsv"
    return row.get("Genotype", "NA") or "NA", row.get("Filter", "NA") or "NA"


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


def _read_json(path: Path) -> object:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _find_value(payload: object, keys: set[str]) -> str:
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


def _smn12_fields(paths: list[Path]) -> dict[str, str]:
    payload = _read_json(Path(_json_path(paths)))
    return {
        "smn1_copy_number": _find_value(payload, {"smn1_cn", "smn1_copy_number", "smn1"}),
        "smn2_copy_number": _find_value(payload, {"smn2_cn", "smn2_copy_number", "smn2"}),
        "affected_status": _find_value(payload, {"issma", "is_sma", "affected_status"}),
        "carrier_status": _find_value(payload, {"iscarrier", "is_carrier", "carrier_status"}),
        "confidence": _find_value(payload, {"confidence", "quality", "filter"}),
    }


def _smaca_fields(paths: list[Path]) -> dict[str, str]:
    rows = _read_tsv_rows(Path(_tsv_path(paths)))
    return {
        "smn1_copy_number": _extract_copy_number(rows, "smn1"),
        "smn2_copy_number": _extract_copy_number(rows, "smn2"),
    }


def _sma_finder_fields(paths: list[Path]) -> dict[str, str]:
    row = _read_first_tsv(Path(_tsv_path(paths)))
    return {
        "smn1_copy_number": "NA",
        "smn2_copy_number": "NA",
        "affected_status": row.get("sma_status", "NA") or "NA",
        "carrier_status": "not_reported",
        "confidence": row.get("confidence_score", "NA") or "NA",
    }


def _hapsma_fields(paths: list[Path]) -> dict[str, str]:
    row = _read_first_tsv(Path(_tsv_path(paths)))
    return {
        "smn1_copy_number": "NA",
        "smn2_copy_number": "NA",
        "affected_status": "not_reported",
        "carrier_status": "not_reported",
        "confidence": row.get("mean_smn_region_coverage", "NA") or "NA",
    }


def _caller_fields(caller: str, paths: list[Path]) -> dict[str, str]:
    defaults = {
        "smn1_copy_number": "NA",
        "smn2_copy_number": "NA",
        "affected_status": "NA",
        "carrier_status": "NA",
        "confidence": "NA",
    }
    if caller == "smn12":
        return {**defaults, **_smn12_fields(paths)}
    if caller == "smaca":
        return {**defaults, **_smaca_fields(paths)}
    if caller == "sma_finder":
        return {**defaults, **_sma_finder_fields(paths)}
    if caller == "hapsma":
        return {**defaults, **_hapsma_fields(paths)}
    return defaults


def _json_path(paths: list[Path]) -> str:
    for path in paths:
        if path.name.endswith(".json"):
            return str(path)
    return "NA"


def _tsv_path(paths: list[Path]) -> str:
    for path in paths:
        if path.name.endswith(".tsv"):
            return str(path)
    return "NA"


def _done_path(paths: list[Path]) -> str:
    for path in paths:
        if path.name.endswith(".done"):
            return str(path)
    return "NA"


def _status(caller: str, paths: list[Path], genotype_filter: str) -> str:
    if caller == "cyrius":
        return genotype_filter
    done = _done_path(paths)
    if done != "NA" and Path(done).exists():
        return "complete"
    if any(path.exists() for path in paths):
        return "partial"
    return "missing"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    groups: dict[tuple[str, str, str, str], list[Path]] = defaultdict(list)
    for raw_path in args.paths:
        match = HTD_RE.search(raw_path)
        if not match:
            continue
        groups[
            (
                match.group("sample"),
                match.group("aligner"),
                match.group("deduper"),
                match.group("caller"),
            )
        ].append(Path(raw_path))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "sample",
        "aligner",
        "deduper",
        "caller",
        "gene",
        "caller_class",
        "evidence_source",
        "genotype",
        "filter",
        "smn1_copy_number",
        "smn2_copy_number",
        "affected_status",
        "carrier_status",
        "confidence",
        "status",
        "json_path",
        "tsv_path",
        "done_path",
        "output_paths",
    ]

    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for sample, aligner, deduper, caller in sorted(groups):
            paths = sorted(groups[(sample, aligner, deduper, caller)])
            genotype = "NA"
            genotype_filter = "NA"
            if caller == "cyrius":
                genotype, genotype_filter = _read_cyrius_tsv(Path(_tsv_path(paths)))
            caller_fields = _caller_fields(caller, paths)
            writer.writerow(
                {
                    "sample": sample,
                    "aligner": aligner,
                    "deduper": deduper,
                    "caller": caller,
                    "gene": GENES.get(caller, "NA"),
                    "caller_class": CALLER_CLASS.get(caller, "unknown"),
                    "evidence_source": EVIDENCE_SOURCE.get(caller, "NA"),
                    "genotype": genotype,
                    "filter": genotype_filter,
                    "smn1_copy_number": caller_fields["smn1_copy_number"],
                    "smn2_copy_number": caller_fields["smn2_copy_number"],
                    "affected_status": caller_fields["affected_status"],
                    "carrier_status": caller_fields["carrier_status"],
                    "confidence": caller_fields["confidence"],
                    "status": _status(caller, paths, genotype_filter),
                    "json_path": _json_path(paths),
                    "tsv_path": _tsv_path(paths),
                    "done_path": _done_path(paths),
                    "output_paths": json.dumps([str(path) for path in paths]),
                }
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
