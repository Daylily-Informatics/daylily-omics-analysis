#!/usr/bin/env python3
"""Intersect a sample diploid BED with a Daylily chromosome chunk."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path


def read_fai(path: Path) -> dict[str, int]:
    contig_lengths: dict[str, int] = {}
    with path.open() as handle:
        for line in handle:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 2:
                raise ValueError(f"Malformed FAI line in {path}: {line.rstrip()}")
            contig_lengths[fields[0]] = int(fields[1])
    if not contig_lengths:
        raise ValueError(f"No contigs found in {path}")
    return contig_lengths


def parse_regions(regions: str, contig_lengths: dict[str, int]) -> dict[str, list[tuple[int, int]]]:
    parsed: dict[str, list[tuple[int, int]]] = defaultdict(list)
    for raw_token in regions.split(","):
        token = raw_token.strip().replace("~", ":")
        if not token:
            continue
        if ":" in token:
            contig, span = token.split(":", 1)
            if "-" not in span:
                raise ValueError(f"Region {raw_token!r} is missing start-end coordinates")
            start_text, end_text = span.split("-", 1)
            start_1based = int(start_text)
            end_1based = int(end_text)
            if start_1based < 1 or end_1based < start_1based:
                raise ValueError(f"Region {raw_token!r} has invalid coordinates")
            if contig not in contig_lengths:
                raise ValueError(f"Region {raw_token!r} contig {contig!r} is absent from the reference FAI")
            start = start_1based - 1
            end = min(end_1based, contig_lengths[contig])
        else:
            contig = token
            if contig not in contig_lengths:
                raise ValueError(f"Region contig {contig!r} is absent from the reference FAI")
            start = 0
            end = contig_lengths[contig]
        if start < end:
            parsed[contig].append((start, end))
    if not parsed:
        raise ValueError("No valid regions were provided")
    return parsed


def read_bed(path: Path) -> dict[str, list[tuple[int, int, list[str]]]]:
    intervals: dict[str, list[tuple[int, int, list[str]]]] = defaultdict(list)
    with path.open() as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 3:
                raise ValueError(f"Malformed BED line in {path}: {line.rstrip()}")
            contig = fields[0]
            start = int(fields[1])
            end = int(fields[2])
            if start < 0 or end < start:
                raise ValueError(f"Invalid BED interval in {path}: {line.rstrip()}")
            intervals[contig].append((start, end, fields[3:]))
    if not intervals:
        raise ValueError(f"No intervals found in {path}")
    return intervals


def intersect(
    bed: dict[str, list[tuple[int, int, list[str]]]],
    regions: dict[str, list[tuple[int, int]]],
) -> list[list[str]]:
    output_rows: list[list[str]] = []
    for contig, region_intervals in regions.items():
        for bed_start, bed_end, rest in bed.get(contig, []):
            for region_start, region_end in region_intervals:
                start = max(bed_start, region_start)
                end = min(bed_end, region_end)
                if start < end:
                    output_rows.append([contig, str(start), str(end), *rest])
    return output_rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regions", required=True, help="Comma-separated contigs or contig:start-end chunks")
    parser.add_argument("--diploid-bed", required=True, type=Path)
    parser.add_argument("--fai", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    contig_lengths = read_fai(args.fai)
    regions = parse_regions(args.regions, contig_lengths)
    diploid_bed = read_bed(args.diploid_bed)
    rows = intersect(diploid_bed, regions)
    if not rows:
        raise ValueError(
            f"No overlap between diploid BED {args.diploid_bed} and requested regions {args.regions!r}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as handle:
        for row in rows:
            handle.write("\t".join(row) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
