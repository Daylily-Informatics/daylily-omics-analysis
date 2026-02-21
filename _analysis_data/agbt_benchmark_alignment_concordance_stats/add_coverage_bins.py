#!/usr/bin/env python3
"""Add PrimaryCoverageBin and SecondaryCoverageBin columns to consolidated TSV."""

import csv
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TSV_PATH = os.path.join(BASE_DIR, "consolidated_concordance.tsv")

# Bin edges: (lower_bound_inclusive, upper_bound_exclusive, bin_value)
# Evaluated in order; first match wins.
BIN_RULES = [
    (0, 0, 0),       # exactly 0
    (0, 2, 1),       # >0 and <2
    (2, 4, 3),
    (4, 6, 5),
    (6, 8, 7),
    (8, 12, 10),
    (12, 19.990, 15),
    (19.990, 30, 25),
    (30, 40, 35),
    (40, 50, 45),
    (50, float("inf"), 50),
]


def coverage_bin(value):
    """Bin a coverage value according to the rules."""
    if value == 0:
        return 0
    for lo, hi, bval in BIN_RULES[1:]:  # skip the ==0 rule
        if lo <= value < hi:
            return bval
    return 50  # fallback for >= 50


def main():
    # Read all rows
    with open(TSV_PATH, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        original_fields = list(reader.fieldnames)
        rows = list(reader)

    print(f"Read {len(rows)} rows, {len(original_fields)} columns")

    # Build new field order: insert PrimaryCoverageBin after Primary_MeasuredMeanCov,
    # SecondaryCoverageBin after Secondary_MeasuredMeanCov
    new_fields = []
    for f in original_fields:
        new_fields.append(f)
        if f == "Primary_MeasuredMeanCov":
            new_fields.append("PrimaryCoverageBin")
        elif f == "Secondary_MeasuredMeanCov":
            new_fields.append("SecondaryCoverageBin")

    print(f"New columns: {len(new_fields)}")
    for i, col in enumerate(new_fields, 1):
        marker = " ← NEW" if col in ("PrimaryCoverageBin", "SecondaryCoverageBin") else ""
        print(f"  {i:2d}. {col}{marker}")

    # Compute bins for each row
    for row in rows:
        pri_val = float(row.get("Primary_MeasuredMeanCov") or 0)
        row["PrimaryCoverageBin"] = coverage_bin(pri_val)

        sec_raw = row.get("Secondary_MeasuredMeanCov", "")
        if sec_raw and float(sec_raw) != 0:
            row["SecondaryCoverageBin"] = coverage_bin(float(sec_raw))
        else:
            row["SecondaryCoverageBin"] = ""

    # Write back
    with open(TSV_PATH, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=new_fields, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nWrote {TSV_PATH}")
    print(f"  {len(rows)} rows, {len(new_fields)} columns")


if __name__ == "__main__":
    main()

