#!/usr/bin/env python3
import csv, re, json

for label, path in [
    ("ILMN", "_analysis_data/ilmn_hg003_prod/giab_concordance_mqc.tsv"),
    ("ONT", "_analysis_data/agbt_ont/giab_concordance_mqc.tsv"),
]:
    print(f"\n=== {label} single-platform (SNPts, giabHC) ===")
    with open(path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row["VariantClass"] != "SNPts":
                continue
            if row.get("ROI", "") != "giabHC":
                continue
            m = re.search(r"-(\d+)x-", row["Sample"])
            if not m:
                continue
            cov = int(m.group(1))
            fs = float(row["Fscore"])
            tp = int(float(row["TP"]))
            fn = int(float(row["FN"]))
            fp = int(float(row["FP"]))
            calc = 2 * tp / (2 * tp + fn + fp) if (2 * tp + fn + fp) > 0 else 0
            flag = "*** MISMATCH ***" if abs(fs - calc) > 0.001 else ""
            print(f"  {cov:>2}x: F={fs:.4f}  TP={tp:>9}  FN={fn:>9}  FP={fp:>9}  calc_F={calc:.4f}  {flag}")

# Check hg38 footprint - larger region means more FP
print("\n=== hg38 footprint examples (larger region = more FP expected) ===")
with open("_analysis_data/hioa_data.json") as f:
    data = json.load(f)

for u in data["units"]:
    c = u.get("concordance_hg38", {}).get("SNPts", {})
    if c and c.get("Fscore", 0) > 0.9:
        fs = c["Fscore"]; tp = c["TP"]; fn = c["FN"]; fp = c["FP"]
        calc = 2*tp / (2*tp + fn + fp) if (2*tp + fn + fp) > 0 else 0
        print(f"  SR{u['sr_cov']:>2}x-ONT{u['ont_cov']:>2}x hg38:    F={fs:.4f}  TP={tp:>9}  FN={fn:>9}  FP={fp:>9}  calc={calc:.4f}")
    c2 = u.get("concordance", {}).get("SNPts", {})
    if c2 and c2.get("Fscore", 0) > 0.9:
        fs = c2["Fscore"]; tp = c2["TP"]; fn = c2["FN"]; fp = c2["FP"]
        calc = 2*tp / (2*tp + fn + fp) if (2*tp + fn + fp) > 0 else 0
        print(f"  SR{u['sr_cov']:>2}x-ONT{u['ont_cov']:>2}x giabHC: F={fs:.4f}  TP={tp:>9}  FN={fn:>9}  FP={fp:>9}  calc={calc:.4f}")

# Check: any cell where FP > 100K and F > 0.9?
print("\n=== Any cell with FP > 100K and F > 0.9? ===")
for u in data["units"]:
    for fp_key, fp_name in [("concordance","giabHC"), ("concordance_clinvar","clinvar"), ("concordance_hg38","hg38")]:
        for cls in ["SNPts","SNPtv","INS_50","INS_gt50","DEL_50","DEL_gt50","Indel_50","Indel_gt50","All"]:
            c = u.get(fp_key, {}).get(cls, {})
            if not c: continue
            if c.get("Fscore",0) > 0.9 and c.get("FP",0) > 100000:
                print(f"  SR{u['sr_cov']:>2}x-ONT{u['ont_cov']:>2}x {fp_name}/{cls}: F={c['Fscore']:.4f} TP={c['TP']} FN={c['FN']} FP={c['FP']}")

