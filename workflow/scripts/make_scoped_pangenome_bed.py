#!/usr/bin/env python3
"""Intersect a pangenome canonical BED with a DayOA shard region."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path


BedRow = tuple[int, int, list[str]]
RegionMap = dict[str, list[tuple[int, int]]]


def read_fai(path: Path) -> dict[str, int]:
    contig_lengths: dict[str, int] = {}
    with path.open(encoding="utf-8") as handle:
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


def parse_regions(regions: str, contig_lengths: dict[str, int]) -> RegionMap:
    parsed: RegionMap = defaultdict(list)
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
    return dict(parsed)


def read_bed(path: Path) -> dict[str, list[BedRow]]:
    intervals: dict[str, list[BedRow]] = defaultdict(list)
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 3:
                raise ValueError(f"Malformed BED line in {path}: {line.rstrip()}")
            contig = fields[0]
            start = int(fields[1])
            end = int(fields[2])
            if start < 0 or end <= start:
                raise ValueError(f"Invalid BED interval in {path}: {line.rstrip()}")
            intervals[contig].append((start, end, fields[3:]))
    if not intervals:
        raise ValueError(f"No intervals found in {path}")
    return dict(intervals)


def intersect(bed: dict[str, list[BedRow]], regions: RegionMap) -> list[list[str]]:
    rows: list[list[str]] = []
    for contig, region_intervals in regions.items():
        for bed_start, bed_end, rest in bed.get(contig, []):
            for region_start, region_end in region_intervals:
                start = max(bed_start, region_start)
                end = min(bed_end, region_end)
                if start < end:
                    rows.append([contig, str(start), str(end), *rest])
    return rows


def write_bed(rows: list[list[str]], output: Path) -> None:
    if not rows:
        raise ValueError("No overlap between canonical BED and requested shard")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write("\t".join(row) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regions", required=True, help="Comma-separated contigs or contig:start-end chunks")
    parser.add_argument("--canonical-bed", required=True, type=Path)
    parser.add_argument("--fai", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    contig_lengths = read_fai(args.fai)
    regions = parse_regions(args.regions, contig_lengths)
    canonical_bed = read_bed(args.canonical_bed)
    rows = intersect(canonical_bed, regions)
    write_bed(rows, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
