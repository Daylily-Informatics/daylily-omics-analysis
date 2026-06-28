#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import TextIO


AUTOSOMES = {f"chr{i}" for i in range(1, 23)} | {str(i) for i in range(1, 23)}
CHR_X = {"chrX", "X"}
CHR_Y = {"chrY", "Y"}
DERIVABLE_RAW_VALUES = {"", "na", "<empty>"}


def _normalize_raw_sex(value: str) -> str:
    text = (value or "").strip().lower()
    return text if text else "<empty>"


def _read_idxstats(fh: TextIO) -> dict[str, tuple[int, int]]:
    records: dict[str, tuple[int, int]] = {}
    for line_no, line in enumerate(fh, start=1):
        fields = line.rstrip("\n").split("\t")
        if len(fields) < 4:
            raise ValueError(f"idxstats line {line_no} has fewer than 4 columns")
        contig = fields[0]
        if contig == "*":
            continue
        try:
            length = int(fields[1])
            mapped = int(fields[2])
        except ValueError as exc:
            raise ValueError(f"idxstats line {line_no} has non-integer length/mapped") from exc
        if length <= 0:
            continue
        records[contig] = (length, mapped)
    return records


def _coverage_proxy(records: dict[str, tuple[int, int]], contigs: set[str]) -> tuple[int, int, float]:
    total_length = 0
    total_mapped = 0
    for contig, (length, mapped) in records.items():
        if contig in contigs:
            total_length += length
            total_mapped += mapped
    if total_length <= 0:
        return 0, 0, 0.0
    return total_mapped, total_length, total_mapped / total_length


def derive_biological_sex(
    records: dict[str, tuple[int, int]],
    *,
    male_y_ratio_min: float,
    male_x_ratio_max: float,
    female_x_ratio_min: float,
    female_y_ratio_max: float,
) -> dict[str, object]:
    auto_mapped, auto_length, auto_cov = _coverage_proxy(records, AUTOSOMES)
    x_mapped, x_length, x_cov = _coverage_proxy(records, CHR_X)
    y_mapped, y_length, y_cov = _coverage_proxy(records, CHR_Y)
    if auto_cov <= 0:
        raise ValueError("cannot derive biological_sex because chr1-22 mapped coverage is zero")
    if x_length <= 0:
        raise ValueError("cannot derive biological_sex because chrX is absent from idxstats")
    if y_length <= 0:
        raise ValueError("cannot derive biological_sex because chrY is absent from idxstats")

    x_ratio = x_cov / auto_cov
    y_ratio = y_cov / auto_cov
    if x_ratio <= male_x_ratio_max:
        sex = "male"
        reason = (
            f"male because chrX/autosome={x_ratio:.6g} <= {male_x_ratio_max:.6g}"
        )
    elif x_ratio >= female_x_ratio_min:
        sex = "female"
        reason = (
            f"female because chrX/autosome={x_ratio:.6g} >= {female_x_ratio_min:.6g}"
        )
    elif y_ratio >= male_y_ratio_min:
        sex = "male"
        reason = (
            f"male because chrY/autosome={y_ratio:.6g} >= {male_y_ratio_min:.6g} "
            f"with chrX/autosome={x_ratio:.6g} below female threshold {female_x_ratio_min:.6g}"
        )
    elif y_ratio <= female_y_ratio_max:
        sex = "female"
        reason = (
            f"female because chrY/autosome={y_ratio:.6g} <= {female_y_ratio_max:.6g} "
            f"with chrX/autosome={x_ratio:.6g} above male threshold {male_x_ratio_max:.6g}"
        )
    else:
        raise ValueError(
            "ambiguous biological_sex coverage proportions: "
            f"chrX/autosome={x_ratio:.6g}, chrY/autosome={y_ratio:.6g}"
        )

    return {
        "autosome_mapped": auto_mapped,
        "autosome_length": auto_length,
        "autosome_depth_proxy": auto_cov,
        "chrX_mapped": x_mapped,
        "chrX_length": x_length,
        "chrX_depth_proxy": x_cov,
        "chrY_mapped": y_mapped,
        "chrY_length": y_length,
        "chrY_depth_proxy": y_cov,
        "chrX_to_autosome": x_ratio,
        "chrY_to_autosome": y_ratio,
        "derived_biological_sex": sex,
        "heuristic": reason,
    }


def _write_row(path: Path, row: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(row), delimiter="\t")
        writer.writeheader()
        writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Derive approved ExpansionHunter biological sex codes from samtools "
            "idxstats chr1-22, chrX, and chrY coverage proportions."
        )
    )
    parser.add_argument("--sample-id", required=True)
    parser.add_argument("--raw-biological-sex", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--male-y-ratio-min", type=float, default=0.05)
    parser.add_argument("--male-x-ratio-max", type=float, default=0.65)
    parser.add_argument("--female-x-ratio-min", type=float, default=0.80)
    parser.add_argument("--female-y-ratio-max", type=float, default=0.03)
    args = parser.parse_args()

    raw_normalized = _normalize_raw_sex(args.raw_biological_sex)
    if raw_normalized not in DERIVABLE_RAW_VALUES:
        raise SystemExit(
            "Refusing to derive biological_sex unless raw BIOLOGICAL_SEX is "
            f"'na' or empty; observed {args.raw_biological_sex!r}."
        )

    records = _read_idxstats(sys.stdin)
    derived = derive_biological_sex(
        records,
        male_y_ratio_min=args.male_y_ratio_min,
        male_x_ratio_max=args.male_x_ratio_max,
        female_x_ratio_min=args.female_x_ratio_min,
        female_y_ratio_max=args.female_y_ratio_max,
    )
    row = {
        "sample_id": args.sample_id,
        "raw_biological_sex": args.raw_biological_sex,
        **derived,
    }
    _write_row(Path(args.output), row)
    print(
        "derived_biological_sex="
        f"{row['derived_biological_sex']} sample_id={args.sample_id} "
        f"chrX_to_autosome={row['chrX_to_autosome']:.6g} "
        f"chrY_to_autosome={row['chrY_to_autosome']:.6g}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
