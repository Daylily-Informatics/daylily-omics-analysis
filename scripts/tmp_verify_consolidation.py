#!/usr/bin/env python3
"""Verify the regenerated consolidated concordance TSV."""
import csv
import sys
from collections import Counter

TSV = "_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv"

with open(TSV, "r") as f:
    reader = csv.DictReader(f, delimiter="\t")
    rows = list(reader)
    fieldnames = reader.fieldnames

total = len(rows)
print(f"Total data rows: {total}")
print(f"Columns ({len(fieldnames)}): {', '.join(fieldnames)}")

# TestGroup counts
tg_counts = Counter(r["TestGroup"] for r in rows)
print(f"\nTestGroups ({len(tg_counts)}):")
for tg, cnt in sorted(tg_counts.items()):
    print(f"  {tg:<35} {cnt:>6}")

# Platform counts
plat_counts = Counter(r["PrimarySeqPlatform"] for r in rows)
print(f"\nPrimarySeqPlatform ({len(plat_counts)}):")
for p, cnt in sorted(plat_counts.items()):
    print(f"  {p:<20} {cnt:>6}")

# Aligner counts
al_counts = Counter(r["Aligner"] for r in rows)
print(f"\nAligners ({len(al_counts)}):")
for a, cnt in sorted(al_counts.items()):
    print(f"  {a:<20} {cnt:>6}")

# Caller counts
cal_counts = Counter(r["SNVCaller"] for r in rows)
print(f"\nSNVCallers ({len(cal_counts)}):")
for c, cnt in sorted(cal_counts.items()):
    print(f"  {c:<20} {cnt:>6}")

# Check for empty VariantClass or ROI
empty_vc = sum(1 for r in rows if not r.get("VariantClass"))
empty_roi = sum(1 for r in rows if not r.get("ROI"))
print(f"\nEmpty VariantClass: {empty_vc}")
print(f"Empty ROI: {empty_roi}")

# Verify expected sum from audit
audit_sum = 720+720+1296+1989+2160+882+2160+1134+3744+648+719+648+1944+504+648+648+216+576+567+144+216+567+144+720
print(f"\nExpected total from audit: {audit_sum}")
print(f"Actual total: {total}")
print(f"Match: {'YES' if total == audit_sum else 'NO - DIFF=' + str(total - audit_sum)}")

# Check GenomeBuild distribution
gb_counts = Counter(r["GenomeBuild"] for r in rows)
print(f"\nGenomeBuild ({len(gb_counts)}):")
for gb, cnt in sorted(gb_counts.items()):
    print(f"  {gb:<20} {cnt:>6}")

