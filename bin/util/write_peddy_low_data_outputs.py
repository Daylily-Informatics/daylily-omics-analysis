#!/usr/bin/env python3
"""Write explicit Peddy QC outputs for VCFs with no usable het calls."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import shutil
from pathlib import Path


PNG_1X1 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8"
    "/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
)


def _peddy_prefix(prefix: str) -> Path:
    return Path(prefix.rstrip(".-"))


def _ped_sex(ped_path: Path) -> str:
    with ped_path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 5:
                return {"1": "male", "2": "female"}.get(fields[4], "unknown")
    return "unknown"


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_outputs(prefix: str, ped_path: Path, sample_id: str, reason: str) -> None:
    out_prefix = _peddy_prefix(prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    status = "insufficient_variant_data"
    ped_sex = _ped_sex(ped_path)

    shutil.copyfile(ped_path, Path(f"{out_prefix}.ped"))
    _write_csv(
        Path(f"{out_prefix}.ped_check.csv"),
        [
            "sample_a",
            "sample_b",
            "rel",
            "hets_a",
            "hets_b",
            "shared_hets",
            "ibs0",
            "ibs2",
            "n",
            "pedigree_parents",
            "pedigree_relatedness",
            "predicted_parents",
            "parent_error",
            "sample_duplication_error",
            "rel_difference",
        ],
        [],
    )
    _write_csv(
        Path(f"{out_prefix}.ped_check.rel-difference.csv"),
        ["sample", "rel_difference"],
        [{"sample": sample_id, "rel_difference": ""}],
    )
    _write_csv(
        Path(f"{out_prefix}.het_check.csv"),
        [
            "sample_id",
            "call_rate",
            "het_ratio",
            "mean_depth",
            "median_depth",
            "depth_outlier",
            "idr_baf",
            "dayoa_status",
            "dayoa_status_detail",
        ],
        [
            {
                "sample_id": sample_id,
                "call_rate": "0",
                "het_ratio": "",
                "mean_depth": "",
                "median_depth": "",
                "depth_outlier": "",
                "idr_baf": "",
                "dayoa_status": status,
                "dayoa_status_detail": reason,
            }
        ],
    )
    _write_csv(
        Path(f"{out_prefix}.sex_check.csv"),
        [
            "sample_id",
            "ped_sex",
            "hom_ref_count",
            "het_count",
            "hom_alt_count",
            "het_ratio",
            "predicted_sex",
            "error",
            "dayoa_status",
            "dayoa_status_detail",
        ],
        [
            {
                "sample_id": sample_id,
                "ped_sex": ped_sex,
                "hom_ref_count": "0",
                "het_count": "0",
                "hom_alt_count": "0",
                "het_ratio": "",
                "predicted_sex": "UNKNOWN",
                "error": "true",
                "dayoa_status": status,
                "dayoa_status_detail": reason,
            }
        ],
    )
    Path(f"{out_prefix}.background_pca.json").write_text(
        json.dumps([], separators=(",", ":")) + "\n", encoding="utf-8"
    )
    for suffix, title in (("html", "Peddy low-data QC"), ("vs.html", "Peddy relatedness low-data QC")):
        Path(f"{out_prefix}.{suffix}").write_text(
            "<!doctype html><html><head><meta charset=\"utf-8\">"
            f"<title>{title}</title></head><body>"
            f"<h1>{title}</h1><p>{status}: {reason}</p></body></html>\n",
            encoding="utf-8",
        )
    png_bytes = base64.b64decode(PNG_1X1)
    for suffix in ("ped_check.png", "het_check.png", "sex_check.png"):
        Path(f"{out_prefix}.{suffix}").write_bytes(png_bytes)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--ped", required=True, type=Path)
    parser.add_argument("--sample-id", required=True)
    parser.add_argument("--reason", required=True)
    args = parser.parse_args()
    write_outputs(args.prefix, args.ped, args.sample_id, args.reason)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
