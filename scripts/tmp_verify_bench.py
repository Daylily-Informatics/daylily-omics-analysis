#!/usr/bin/env python3
"""Verify bench_heatmaps.py aggregation against manual calculations.

Manual data gathered from raw TSVs:
  dark_horses2, I2-HG003-30x, sent+clair3:
    27 task rows, TOTAL_COST=$20.63, TOTAL_SECS=38170.3s
  ilmn_all_downsamples_a, I2-HG003-30x, sent+sentd:
    4 calling rows, CALLING_COST=$0.85, CALLING_SECS=3319.7s
    3 shared alignment rows, SHARED_ALIGN_COST=$1.63, SHARED_ALIGN_SECS=2765.9s
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__),
    "..", "_analysis_data", "agbt_benchmark_alignment_concordance_stats"))

from bench_heatmaps import load_benchmarks, classify_stage, extract_aligner_caller
import csv, glob

BASE = os.path.join(os.path.dirname(__file__), "..",
    "_analysis_data", "agbt_benchmark_alignment_concordance_stats", "src_data")

print("=" * 70)
print("TEST 1: dark_horses2, I2-HG003-30x-*, sent+clair3")
print("=" * 70)
fpath = os.path.join(BASE, "dark_horses2", "benchmarks_summary.tsv")
total_cost = 0.0
total_secs = 0.0
rows_matched = 0
with open(fpath) as f:
    for row in csv.DictReader(f, delimiter="\t"):
        sample = row["sample"]
        if "I2-HG003-30x" not in sample:
            continue
        rule = row["rule"]
        aligner, caller = extract_aligner_caller(rule)
        stage = classify_stage(rule)
        cost = float(row.get("task_cost", 0))
        secs = float(row.get("s", 0))
        if stage == "skip":
            print(f"  SKIP: {rule:50s} al={aligner:10s} ca={caller:15s} cost={cost:.4f} secs={secs:.1f}")
            continue
        if caller == "clair3" or (caller in ("_align_only_", "_unknown_") and aligner == "sent"):
            rows_matched += 1
            total_cost += cost
            total_secs += secs
            print(f"  INCL: {rule:50s} al={aligner:10s} ca={caller:15s} st={stage:12s} cost={cost:.4f} secs={secs:.1f}")
        else:
            print(f"  OTHR: {rule:50s} al={aligner:10s} ca={caller:15s} st={stage:12s} cost={cost:.4f} secs={secs:.1f}")

print(f"\n  Rows matched: {rows_matched}")
print(f"  Sum cost: ${total_cost:.2f}  (expected ~$20.63)")
print(f"  Sum secs: {total_secs:.1f}s  (expected ~38170.3s)")

print("\n" + "=" * 70)
print("TEST 2: ilmn_all_downsamples_a, I2-HG003-30x-*, sent+sentd")
print("=" * 70)
fpath2 = os.path.join(BASE, "ilmn_all_downsamples_a", "benchmarks_summary.tsv")
call_cost = 0.0
call_secs = 0.0
align_cost = 0.0
align_secs = 0.0
with open(fpath2) as f:
    for row in csv.DictReader(f, delimiter="\t"):
        sample = row["sample"]
        if "I2-HG003-30x" not in sample:
            continue
        rule = row["rule"]
        aligner, caller = extract_aligner_caller(rule)
        stage = classify_stage(rule)
        cost = float(row.get("task_cost", 0))
        secs = float(row.get("s", 0))
        if stage == "skip":
            print(f"  SKIP: {rule:50s} al={aligner:10s} ca={caller:15s} cost={cost:.4f} secs={secs:.1f}")
            continue
        if caller == "sentd":
            call_cost += cost
            call_secs += secs
            print(f"  CALL: {rule:50s} al={aligner:10s} ca={caller:15s} st={stage:12s} cost={cost:.4f} secs={secs:.1f}")
        elif caller in ("_align_only_", "_unknown_") and aligner == "sent":
            align_cost += cost
            align_secs += secs
            print(f"  ALGN: {rule:50s} al={aligner:10s} ca={caller:15s} st={stage:12s} cost={cost:.4f} secs={secs:.1f}")
        else:
            print(f"  OTHR: {rule:50s} al={aligner:10s} ca={caller:15s} st={stage:12s} cost={cost:.4f} secs={secs:.1f}")

print(f"\n  Calling cost: ${call_cost:.2f}  (expected ~$0.85)")
print(f"  Calling secs: {call_secs:.1f}s  (expected ~3319.7s)")
print(f"  Shared align cost: ${align_cost:.2f}  (expected ~$1.63)")
print(f"  Shared align secs: {align_secs:.1f}s  (expected ~2765.9s)")

print("\n" + "=" * 70)
print("TEST 3: Run load_benchmarks() and check (sent, clair3) and (sent, sentd)")
print("=" * 70)
result = load_benchmarks()
for key in sorted(result.keys()):
    al, ca = key
    r = result[key]
    n = len(r["total_cost"])
    avg_cost = sum(r["total_cost"]) / n if n else 0
    avg_secs = sum(r["total_secs"]) / n if n else 0
    print(f"  ({al:15s}, {ca:12s}): n={n:3d} samples, "
          f"avg_cost=${avg_cost:8.2f}, avg_secs={avg_secs:10.1f}s, "
          f"total_cost=${sum(r['total_cost']):8.2f}")

print("\nDone.")

