#!/usr/bin/env python3
"""Inventory staged Ultima objects in the lsmc-ssf bucket."""

from __future__ import annotations

import argparse
import collections
import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import PurePosixPath
from typing import Iterable

import boto3


@dataclass
class SampleSummary:
    sample: str
    object_count: int = 0
    total_bytes: int = 0
    cram_count: int = 0
    crai_count: int = 0
    edv_vcf_count: int = 0
    edv_gvcf_count: int = 0
    cnv_count: int = 0
    segdup_count: int = 0
    str_count: int = 0
    pgx_count: int = 0
    hla_count: int = 0
    qc_count: int = 0
    individual_run_count: int = 0
    other_count: int = 0
    first_modified: str = ""
    last_modified: str = ""
    example_keys: list[str] | None = None


def classify_key(key: str) -> str:
    parts = PurePosixPath(key).parts
    if "/cram/" in f"/{key}":
        if key.endswith(".crai"):
            return "crai"
        if key.endswith(".cram"):
            return "cram"
    if "/edv/gvcf/" in f"/{key}":
        return "edv_gvcf"
    if "/edv/" in f"/{key}" or "/edv_chrM/" in f"/{key}":
        return "edv_vcf"
    if "/cnv/" in f"/{key}":
        return "cnv"
    if "/segdup/" in f"/{key}":
        return "segdup"
    if "/str/" in f"/{key}":
        return "str"
    if "/pgx/" in f"/{key}":
        return "pgx"
    if "/hla/" in f"/{key}":
        return "hla"
    if "/qc/" in f"/{key}":
        return "qc"
    if "/individual_runs/" in f"/{key}":
        return "individual_run"
    return "other"


def sample_from_key(prefix: str, key: str) -> str:
    rel = key[len(prefix) :].lstrip("/")
    parts = PurePosixPath(rel).parts
    if len(parts) < 2:
        return "_prefix"
    if parts[0] in {"40x", "30x", "20x", "10x", "5x"}:
        return parts[1]
    return parts[0]


def iter_objects(client, bucket: str, prefix: str) -> Iterable[dict]:
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            yield obj


def iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_inventory(profile: str, region: str, bucket: str, prefix: str) -> dict:
    session = boto3.Session(profile_name=profile, region_name=region)
    client = session.client("s3")
    samples: dict[str, SampleSummary] = {}
    class_counts = collections.Counter()
    total_objects = 0
    total_bytes = 0
    all_first: str | None = None
    all_last: str | None = None

    for obj in iter_objects(client, bucket, prefix):
        key = obj["Key"]
        size = int(obj.get("Size", 0))
        modified = iso(obj["LastModified"])
        sample = sample_from_key(prefix, key)
        summary = samples.setdefault(sample, SampleSummary(sample=sample, example_keys=[]))
        cls = classify_key(key)

        total_objects += 1
        total_bytes += size
        class_counts[cls] += 1
        summary.object_count += 1
        summary.total_bytes += size
        setattr(summary, f"{cls}_count", getattr(summary, f"{cls}_count") + 1)

        if not summary.first_modified or modified < summary.first_modified:
            summary.first_modified = modified
        if not summary.last_modified or modified > summary.last_modified:
            summary.last_modified = modified
        if len(summary.example_keys or []) < 5:
            summary.example_keys.append(key)

        if all_first is None or modified < all_first:
            all_first = modified
        if all_last is None or modified > all_last:
            all_last = modified

    sample_rows = [asdict(samples[name]) for name in sorted(samples)]
    for row in sample_rows:
        row["example_keys"] = row["example_keys"] or []

    return {
        "profile": profile,
        "region": region,
        "bucket": bucket,
        "prefix": prefix,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "total_objects": total_objects,
        "total_bytes": total_bytes,
        "first_modified": all_first,
        "last_modified": all_last,
        "class_counts": dict(sorted(class_counts.items())),
        "sample_count": len(samples),
        "samples": sample_rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--bucket", default="lsmc-ssf-sequencing-data")
    parser.add_argument(
        "--prefix",
        default="staged_external_data/23andMePilot/ultima/",
    )
    parser.add_argument("--json-output", required=True)
    parser.add_argument("--tsv-output", required=True)
    args = parser.parse_args()

    inventory = build_inventory(args.profile, args.region, args.bucket, args.prefix)
    with open(args.json_output, "w", encoding="utf-8") as handle:
        json.dump(inventory, handle, indent=2, sort_keys=True)
        handle.write("\n")

    fields = [
        "sample",
        "object_count",
        "total_bytes",
        "cram_count",
        "crai_count",
        "edv_vcf_count",
        "edv_gvcf_count",
        "cnv_count",
        "segdup_count",
        "str_count",
        "pgx_count",
        "hla_count",
        "qc_count",
        "individual_run_count",
        "other_count",
        "first_modified",
        "last_modified",
    ]
    with open(args.tsv_output, "w", encoding="utf-8") as handle:
        handle.write("\t".join(fields) + "\n")
        for row in inventory["samples"]:
            handle.write("\t".join(str(row[field]) for field in fields) + "\n")
    print(json.dumps({k: inventory[k] for k in ("sample_count", "total_objects", "total_bytes", "class_counts")}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
