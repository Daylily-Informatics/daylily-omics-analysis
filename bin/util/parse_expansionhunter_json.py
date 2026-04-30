#!/usr/bin/env python3
"""Parse ExpansionHunter JSON results into a stable STRchive-annotated TSV."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any


HEADER = [
    "sample",
    "aligner",
    "deduper",
    "locus_id",
    "variant_id",
    "variant_type",
    "variant_subtype",
    "gene",
    "disease",
    "inheritance_mode",
    "hgnc_id",
    "catalog_reference_region",
    "variant_reference_region",
    "pathologic_region",
    "locus_structure",
    "display_repeat_unit",
    "repeat_unit",
    "genotype",
    "genotype_confidence_interval",
    "max_allele",
    "coverage",
    "allele_count",
    "normal_max",
    "pathologic_min",
    "status",
]

STATUS_NORMAL = "normal"
STATUS_PATHOGENIC = "pathogenic_range"
STATUS_UNCERTAIN = "intermediate_or_uncertain"
STATUS_NO_CALL = "no_call"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Parse ExpansionHunter JSON plus STRchive catalog into TSV.",
    )
    parser.add_argument("expansionhunter_json", help="ExpansionHunter JSON result file")
    parser.add_argument("strchive_catalog", help="STRchive stranger JSON catalog")
    parser.add_argument(
        "-o",
        "--output",
        default="-",
        help="Output TSV path, or '-' for stdout (default: stdout)",
    )
    parser.add_argument("--sample-id", default=None, help="Sample ID override")
    parser.add_argument("--aligner", default=None, help="Aligner label to include in the TSV")
    parser.add_argument("--deduper", default=None, help="Deduper label to include in the TSV")
    return parser.parse_args(argv)


def load_json(path: Path, label: str) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise ValueError(f"malformed {label} JSON: {path}: {exc}") from exc
    except OSError as exc:
        raise ValueError(f"cannot read {label} JSON: {path}: {exc}") from exc


def as_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return ",".join(as_text(item) for item in value)
    if isinstance(value, dict):
        return json.dumps(value, sort_keys=True, separators=(",", ":"))
    return str(value)


def as_number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def get_sample_id(data: dict[str, Any], json_path: Path, override: str | None) -> str:
    if override:
        return override
    sample_parameters = data.get("SampleParameters")
    if isinstance(sample_parameters, dict):
        for key in ("SampleId", "SampleID", "SampleName", "sample_id", "sample"):
            value = sample_parameters.get(key)
            if value:
                return str(value)
    name = json_path.name
    for suffix in (".eh.json", ".json"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return json_path.stem


def infer_run_labels(json_path: Path, aligner: str | None, deduper: str | None) -> tuple[str, str]:
    if aligner is not None or deduper is not None:
        return aligner or "", deduper or ""
    name = json_path.name
    if name.endswith(".eh.json"):
        stem = name[: -len(".eh.json")]
    elif name.endswith(".json"):
        stem = name[: -len(".json")]
    else:
        stem = json_path.stem
    parts = stem.split(".")
    if len(parts) >= 3:
        return parts[-2], parts[-1]
    return "", ""


def catalog_records(catalog: Any) -> list[dict[str, Any]]:
    if isinstance(catalog, list):
        records = catalog
    elif isinstance(catalog, dict) and isinstance(catalog.get("Loci"), list):
        records = catalog["Loci"]
    else:
        raise ValueError("STRchive catalog must be a JSON array or an object with a Loci array")
    bad = [idx for idx, record in enumerate(records) if not isinstance(record, dict) or "LocusId" not in record]
    if bad:
        raise ValueError(f"STRchive catalog records missing LocusId at indexes: {','.join(map(str, bad[:10]))}")
    return records


def build_catalog_by_locus(catalog: Any) -> dict[str, dict[str, Any]]:
    by_locus: dict[str, dict[str, Any]] = {}
    for record in catalog_records(catalog):
        locus_id = str(record["LocusId"])
        if locus_id in by_locus:
            raise ValueError(f"duplicate STRchive LocusId: {locus_id}")
        by_locus[locus_id] = record
    return by_locus


def item_for_variant(record: dict[str, Any], key: str, variant_id: str) -> Any:
    value = record.get(key)
    if not isinstance(value, list):
        return value
    variant_ids = record.get("VariantId")
    if isinstance(variant_ids, list):
        for index, candidate in enumerate(variant_ids):
            if str(candidate) == variant_id and index < len(value):
                return value[index]
    if len(value) == 1:
        return value[0]
    return value


def iter_locus_results(data: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    if "LocusResults" not in data:
        raise ValueError("ExpansionHunter JSON is missing required LocusResults")
    locus_results = data["LocusResults"]
    if isinstance(locus_results, dict):
        results = []
        for locus_key, locus_result in locus_results.items():
            if not isinstance(locus_result, dict):
                raise ValueError(f"LocusResults[{locus_key!r}] is not an object")
            locus_id = str(locus_result.get("LocusId") or locus_key)
            results.append((locus_id, locus_result))
        return results
    if isinstance(locus_results, list):
        results = []
        for index, locus_result in enumerate(locus_results):
            if not isinstance(locus_result, dict):
                raise ValueError(f"LocusResults[{index}] is not an object")
            locus_id = locus_result.get("LocusId")
            if not locus_id:
                raise ValueError(f"LocusResults[{index}] is missing LocusId")
            results.append((str(locus_id), locus_result))
        return results
    raise ValueError("ExpansionHunter LocusResults must be an object or array")


def iter_variants(locus_id: str, locus_result: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    variants = locus_result.get("Variants")
    if variants is None:
        return [(locus_id, {})]
    if isinstance(variants, dict):
        result = []
        for variant_key, variant in variants.items():
            if not isinstance(variant, dict):
                raise ValueError(f"Variants[{variant_key!r}] for {locus_id} is not an object")
            result.append((str(variant.get("VariantId") or variant_key), variant))
        return result
    if isinstance(variants, list):
        result = []
        for index, variant in enumerate(variants):
            if not isinstance(variant, dict):
                raise ValueError(f"Variants[{index}] for {locus_id} is not an object")
            result.append((str(variant.get("VariantId") or f"{locus_id}:{index + 1}"), variant))
        return result
    raise ValueError(f"Variants for {locus_id} must be an object or array")


def parse_genotype_alleles(genotype: Any) -> list[float]:
    if genotype is None:
        return []
    if isinstance(genotype, list):
        values = genotype
    else:
        text = str(genotype).strip()
        if not text or text in {".", "./.", ".|."}:
            return []
        values = re.split(r"[/|,; ]+", text)
    alleles = []
    for value in values:
        if value in (None, "", "."):
            continue
        number = as_number(value)
        if number is None:
            return []
        alleles.append(number)
    return alleles


def classify_status(genotype: Any, normal_max: Any, pathologic_min: Any) -> tuple[str, str]:
    alleles = parse_genotype_alleles(genotype)
    if not alleles:
        return STATUS_NO_CALL, ""

    max_allele = max(alleles)
    pathologic_threshold = as_number(pathologic_min)
    normal_threshold = as_number(normal_max)
    if pathologic_threshold is not None and max_allele >= pathologic_threshold:
        return STATUS_PATHOGENIC, f"{max_allele:g}"
    if normal_threshold is not None and all(allele <= normal_threshold for allele in alleles):
        return STATUS_NORMAL, f"{max_allele:g}"
    return STATUS_UNCERTAIN, f"{max_allele:g}"


def build_rows(
    eh_data: dict[str, Any],
    catalog_by_locus: dict[str, dict[str, Any]],
    sample_id: str,
    aligner: str,
    deduper: str,
) -> list[dict[str, str]]:
    rows = []
    for locus_id, locus_result in iter_locus_results(eh_data):
        catalog_record = catalog_by_locus.get(locus_id, {})
        for variant_id, variant in iter_variants(locus_id, locus_result):
            normal_max = catalog_record.get("NormalMax")
            pathologic_min = catalog_record.get("PathologicMin")
            status, max_allele = classify_status(variant.get("Genotype"), normal_max, pathologic_min)
            rows.append(
                {
                    "sample": sample_id,
                    "aligner": aligner,
                    "deduper": deduper,
                    "locus_id": locus_id,
                    "variant_id": variant_id,
                    "variant_type": as_text(variant.get("VariantType") or item_for_variant(catalog_record, "VariantType", variant_id)),
                    "variant_subtype": as_text(variant.get("VariantSubtype")),
                    "gene": as_text(catalog_record.get("Gene")),
                    "disease": as_text(catalog_record.get("Disease")),
                    "inheritance_mode": as_text(catalog_record.get("InheritanceMode")),
                    "hgnc_id": as_text(catalog_record.get("HGNCId")),
                    "catalog_reference_region": as_text(item_for_variant(catalog_record, "ReferenceRegion", variant_id)),
                    "variant_reference_region": as_text(variant.get("ReferenceRegion")),
                    "pathologic_region": as_text(catalog_record.get("PathologicRegion")),
                    "locus_structure": as_text(catalog_record.get("LocusStructure")),
                    "display_repeat_unit": as_text(catalog_record.get("DisplayRU")),
                    "repeat_unit": as_text(variant.get("RepeatUnit")),
                    "genotype": as_text(variant.get("Genotype")),
                    "genotype_confidence_interval": as_text(variant.get("GenotypeConfidenceInterval")),
                    "max_allele": max_allele,
                    "coverage": as_text(locus_result.get("Coverage")),
                    "allele_count": as_text(locus_result.get("AlleleCount")),
                    "normal_max": as_text(normal_max),
                    "pathologic_min": as_text(pathologic_min),
                    "status": status,
                }
            )
    rows.sort(key=lambda row: (row["locus_id"], row["variant_id"]))
    return rows


def write_tsv(rows: list[dict[str, str]], output: str) -> None:
    if output == "-":
        writer = csv.DictWriter(sys.stdout, fieldnames=HEADER, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        return
    output_path = Path(output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=HEADER, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    eh_path = Path(args.expansionhunter_json)
    catalog_path = Path(args.strchive_catalog)
    try:
        eh_data = load_json(eh_path, "ExpansionHunter")
        if not isinstance(eh_data, dict):
            raise ValueError("ExpansionHunter JSON root must be an object")
        catalog = load_json(catalog_path, "STRchive catalog")
        catalog_by_locus = build_catalog_by_locus(catalog)
        sample_id = get_sample_id(eh_data, eh_path, args.sample_id)
        aligner, deduper = infer_run_labels(eh_path, args.aligner, args.deduper)
        rows = build_rows(eh_data, catalog_by_locus, sample_id, aligner, deduper)
        write_tsv(rows, args.output)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
