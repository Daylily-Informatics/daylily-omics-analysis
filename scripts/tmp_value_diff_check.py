#!/usr/bin/env python3
"""Check if 'duplicate' dirs have different metric values vs consolidated."""
import csv
import os

BD = "_analysis_data/agbt_benchmark_alignment_concordance_stats/src_data"
CONSOL = "_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv"

DUPLICATE_DIRS = ["hiomr_three", "hiomr_four", "ilmn_fin_pan2",
                  "pangenome_A", "pangenome_B"]

METRICS = ["Fscore", "Sensitivity-Recall", "Precision", "TP", "FP", "FN", "TN"]


def make_key(row):
    return (row["Sample"], row["Aligner"], row["SNVCaller"],
            row["VariantClass"], row["ROI"])


def load_tsv(path):
    rows = []
    with open(path, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(dict(row))
    return rows


# Load consolidated and index by key
print("Loading consolidated TSV ...")
consol_rows = load_tsv(CONSOL)
consol_by_key = {}
for r in consol_rows:
    k = make_key(r)
    consol_by_key[k] = r

print(f"  {len(consol_rows)} rows loaded\n")

for dname in DUPLICATE_DIRS:
    path = os.path.join(BD, dname, "giab_concordance_mqc.tsv")
    if not os.path.exists(path):
        continue
    dir_rows = load_tsv(path)

    diffs = 0
    identical = 0
    missing_in_consol = 0
    diff_details = []

    for r in dir_rows:
        k = make_key(r)
        if k not in consol_by_key:
            missing_in_consol += 1
            continue

        cr = consol_by_key[k]
        row_diffs = []
        for m in METRICS:
            v_dir = r.get(m, "")
            v_con = cr.get(m, "")
            try:
                f_dir = float(v_dir) if v_dir else 0.0
                f_con = float(v_con) if v_con else 0.0
                if abs(f_dir - f_con) > 1e-10:
                    row_diffs.append((m, v_dir, v_con))
            except ValueError:
                if v_dir != v_con:
                    row_diffs.append((m, v_dir, v_con))

        if row_diffs:
            diffs += 1
            if len(diff_details) < 3:
                diff_details.append((k, row_diffs))
        else:
            identical += 1

    print(f"--- {dname} ({len(dir_rows)} rows) ---")
    print(f"  Identical to consolidated: {identical}")
    print(f"  DIFFERENT values: {diffs}")
    print(f"  Not found in consolidated: {missing_in_consol}")
    if diff_details:
        for k, rd in diff_details:
            print(f"  Example diff: {k[:3]}...")
            for m, vd, vc in rd:
                print(f"    {m}: dir={vd}  consol={vc}")
    print()

