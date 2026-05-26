#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--objects-json", required=True, type=Path)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--zero-markers", required=True, type=Path)
    args = parser.parse_args()

    payload = json.loads(args.objects_json.read_text(encoding="utf-8"))
    rows: list[tuple[str, int]] = []
    zero_markers = 0
    prefix = args.prefix
    if not prefix.endswith("/"):
        prefix += "/"

    for obj in payload.get("Contents", []) or []:
        key = obj["Key"]
        size = int(obj["Size"])
        if not key.startswith(prefix):
            raise SystemExit(f"object key does not start with prefix: {key}")
        relpath = key[len(prefix):]
        if not relpath:
            continue
        if "/_daylily_monitor/" in f"/{relpath}":
            continue
        if size == 0 and key.endswith("/"):
            zero_markers += 1
            continue
        rows.append((relpath, size))

    rows.sort()
    args.manifest.write_text(
        "".join(f"{path}\t{size}\n" for path, size in rows),
        encoding="utf-8",
    )
    args.zero_markers.write_text(f"{zero_markers}\n", encoding="utf-8")
    print(f"s3_file_objects={len(rows)}")
    print(f"zero_byte_s3_directory_markers_ignored={zero_markers}")
    print(f"s3_bytes={sum(size for _, size in rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
