#!/usr/bin/env python3
"""Full row-level dedup analysis of 7 unprocessed src_data dirs vs consolidated TSV."""
import csv
import os
from collections import defaultdict

BD = "_analysis_data/agbt_benchmark_alignment_concordance_stats/src_data"
CONSOL = "_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv"

UNPROCESSED = ["RLEN", "hiomr_three", "hiomr_four", "ilmn_fin_pan2",
               "pangenome_A", "pangenome_B", "read_len"]


def make_key(row):
    """Unique row key: (Sample, Aligner, SNVCaller, VariantClass, ROI)."""
    return (row["Sample"], row["Aligner"], row["SNVCaller"],
            row["VariantClass"], row["ROI"])


def load_tsv(path):
    """Load all rows from a concordance TSV, return list of dicts."""
    rows = []
    with open(path, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(dict(row))
    return rows


# --- Load consolidated TSV ---
print("Loading consolidated_concordance.tsv ...")
consol_rows = load_tsv(CONSOL)
consol_keys = set()
for r in consol_rows:
    consol_keys.add(make_key(r))
print(f"  {len(consol_rows)} rows, {len(consol_keys)} unique keys\n")

# --- Load each unprocessed directory ---
dir_data = {}
for dname in UNPROCESSED:
    path = os.path.join(BD, dname, "giab_concordance_mqc.tsv")
    if not os.path.exists(path):
        print(f"SKIP: {dname} - no concordance file")
        continue
    rows = load_tsv(path)
    dir_data[dname] = rows
    print(f"{dname}: {len(rows)} rows")

print("\n" + "=" * 80)
print("ANALYSIS: Each dir vs consolidated TSV")
print("=" * 80)

all_new_keys = {}  # key -> list of (dname, row)

for dname, rows in dir_data.items():
    keys_in_dir = set()
    dup_in_consol = 0
    new_rows = 0
    samples = set()
    aligners = set()
    callers = set()
    rois = set()
    vclasses = set()

    for r in rows:
        k = make_key(r)
        keys_in_dir.add(k)
        samples.add(r["Sample"])
        aligners.add(r["Aligner"])
        callers.add(r["SNVCaller"])
        rois.add(r["ROI"])
        vclasses.add(r["VariantClass"])

        if k in consol_keys:
            dup_in_consol += 1
        else:
            new_rows += 1
            if k not in all_new_keys:
                all_new_keys[k] = []
            all_new_keys[k].append((dname, r))

    print(f"\n--- {dname} ({len(rows)} rows, {len(keys_in_dir)} unique keys) ---")
    print(f"  Already in consolidated: {dup_in_consol}")
    print(f"  NEW (not in consolidated): {new_rows}")
    print(f"  Samples: {sorted(samples)}")
    print(f"  Aligners: {sorted(aligners)}")
    print(f"  Callers: {sorted(callers)}")
    print(f"  ROIs: {sorted(rois)}")
    print(f"  VariantClasses: {sorted(vclasses)}")

print("\n" + "=" * 80)
print("ANALYSIS: Cross-directory duplicates among unprocessed dirs")
print("=" * 80)

# Check for keys that appear in multiple unprocessed dirs
cross_dups = defaultdict(list)
for dname, rows in dir_data.items():
    for r in rows:
        k = make_key(r)
        if k not in consol_keys:  # only check new keys
            cross_dups[k].append(dname)

multi = {k: dirs for k, dirs in cross_dups.items() if len(dirs) > 1}
if multi:
    # Group by pair of dirs
    pair_counts = defaultdict(int)
    for k, dirs in multi.items():
        pair = tuple(sorted(set(dirs)))
        pair_counts[pair] += 1
    print(f"\n  {len(multi)} keys appear in multiple unprocessed dirs:")
    for pair, cnt in sorted(pair_counts.items(), key=lambda x: -x[1]):
        print(f"    {' + '.join(pair)}: {cnt} shared keys")

    # Show a few examples
    shown = 0
    for k, dirs in list(multi.items())[:5]:
        print(f"    Example: {k} -> {dirs}")
        # Compare Fscores
        for dname, rows_list in all_new_keys[k]:
            print(f"      {dname}: Fscore={rows_list['Fscore']}")
        shown += 1
else:
    print("\n  No cross-directory duplicates among new keys.")

print("\n" + "=" * 80)
print("SUMMARY: Total new rows to add")
print("=" * 80)

total_new = 0
for dname, rows in dir_data.items():
    new_count = sum(1 for r in rows if make_key(r) not in consol_keys)
    total_new += new_count
    print(f"  {dname}: {new_count} new rows")
print(f"  TOTAL new rows (before cross-dedup): {total_new}")

# After cross-dedup (keep first occurrence)
seen = set()
unique_new = 0
for dname in UNPROCESSED:
    if dname not in dir_data:
        continue
    for r in dir_data[dname]:
        k = make_key(r)
        if k not in consol_keys and k not in seen:
            seen.add(k)
            unique_new += 1
print(f"  TOTAL unique new rows (after cross-dedup): {unique_new}")

