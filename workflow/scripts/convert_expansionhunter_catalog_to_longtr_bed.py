#!/usr/bin/env python3
"""Convert a simple ExpansionHunter JSON catalog into a LongTR BED catalog."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REGION_RE = re.compile(r"^(?P<chrom>[^:]+):(?P<start>[0-9]+)-(?P<end>[0-9]+)$")
MOTIF_RE = re.compile(r"\(([A-Za-zN]+)\)\*")


def _read_catalog(path: Path) -> list[dict[str, Any]]:
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8") as handle:
            data = json.load(handle)
    else:
        data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("ExpansionHunter catalog must be a JSON list")
    return data


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _as_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    return [value]


def _motifs(entry: dict[str, Any]) -> list[str]:
    structure = str(entry.get("LocusStructure", "") or "")
    parsed = MOTIF_RE.findall(structure)
    if parsed:
        return parsed
    display = str(entry.get("DisplayRU", "") or "").strip()
    if display:
        return [display]
    return []


def _name_for(entry: dict[str, Any], index: int, total: int) -> str:
    variant_ids = _as_list(entry.get("VariantId", []))
    if index < len(variant_ids) and str(variant_ids[index]).strip():
        return str(variant_ids[index]).strip()
    locus_id = str(entry.get("LocusId", "") or "").strip()
    if not locus_id:
        locus_id = f"locus_{index + 1}"
    if total > 1:
        return f"{locus_id}_part{index + 1}"
    return locus_id


def convert(catalog: list[dict[str, Any]]) -> tuple[list[str], list[str]]:
    rows: list[tuple[str, int, int, str, str]] = []
    skipped: list[str] = []
    for entry in catalog:
        regions = [str(region) for region in _as_list(entry.get("ReferenceRegion", []))]
        motifs = _motifs(entry)
        if not regions:
            skipped.append(f"{entry.get('LocusId', '')}\tmissing_reference_region")
            continue
        if not motifs:
            skipped.append(f"{entry.get('LocusId', '')}\tmissing_repeat_motif")
            continue
        for index, region in enumerate(regions):
            match = REGION_RE.match(region)
            if not match:
                skipped.append(f"{entry.get('LocusId', '')}\tunsupported_region\t{region}")
                continue
            chrom = match.group("chrom")
            eh_start = int(match.group("start"))
            eh_end = int(match.group("end"))
            start_1based = eh_start + 1
            if start_1based > eh_end:
                skipped.append(
                    f"{entry.get('LocusId', '')}\tnon_positive_interval_after_1based_conversion\t{region}"
                )
                continue
            motif = motifs[index] if index < len(motifs) else motifs[-1]
            name = _name_for(entry, index, len(regions))
            rows.append((chrom, start_1based, eh_end, motif, name))
    rows.sort(key=lambda row: (row[0], row[1], row[2], row[4]))
    bed_rows = ["\t".join(map(str, row)) for row in rows]
    return bed_rows, skipped


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Convert an ExpansionHunter JSON catalog to the LongTR five-column "
            "BED contract: chrom, 1-based start, end, motif, name."
        )
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-bed", required=True, type=Path)
    parser.add_argument("--manifest-json", required=True, type=Path)
    parser.add_argument("--skipped-tsv", required=True, type=Path)
    parser.add_argument("--source-name", required=True)
    parser.add_argument("--genome-build", required=True)
    args = parser.parse_args()

    catalog = _read_catalog(args.input)
    rows, skipped = convert(catalog)
    if not rows:
        raise ValueError("No LongTR-compatible rows were produced")

    args.output_bed.parent.mkdir(parents=True, exist_ok=True)
    args.output_bed.write_text("\n".join(rows) + "\n", encoding="utf-8")
    args.skipped_tsv.write_text(
        "locus_id\treason\tdetail\n"
        + "\n".join(
            line if line.count("\t") >= 2 else f"{line}\t" for line in skipped
        )
        + ("\n" if skipped else ""),
        encoding="utf-8",
    )

    manifest = {
        "catalog_name": "disease_repeat_catalog",
        "converter": Path(__file__).name,
        "coordinate_contract": "LongTR BED with 1-based start and inclusive end",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "genome_build": args.genome_build,
        "input_catalog": str(args.input),
        "input_sha256": _sha256(args.input),
        "output_bed": str(args.output_bed),
        "output_bed_sha256": _sha256(args.output_bed),
        "output_rows": len(rows),
        "skipped_rows": len(skipped),
        "source_name": args.source_name,
    }
    args.manifest_json.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
