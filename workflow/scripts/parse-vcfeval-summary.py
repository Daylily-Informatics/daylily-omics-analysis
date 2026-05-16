
""" Take rtg vcfeval summary.txt file, pull out the 'None' filtered data and regurigtate it with some add'l values calc'd"""
import csv
import os
import sys
import re

if len(sys.argv) < 11:
    raise SystemExit(
        "usage: parse-vcfeval-summary.py summary sample truth_bed roi alt_id "
        "legacy_out allvar_mean_dp aligner deduper snv_caller"
    )

def _get_int_env(var_name, default):
    try:
        v = os.environ.get(var_name)
        if v is None or str(v).strip() == "":
            return int(default)
        return int(float(str(v)))
    except Exception:
        return int(default)

# bcftools/threading: keep legacy default (cpu_count//4) but allow overriding
cpus_div4 = max(1, _get_int_env("DAYLILY_BCFTOOLS_THREADS", os.cpu_count() // 4))  # Integer division legacy default

summary_fh = open(sys.argv[1], "r")
sample = sys.argv[2]  # Sample name
tgt_region_bed = sys.argv[3]  # bed  file of the regions used in vcf eval
cmp_footprint = sys.argv[4]  # Replaced treatment
subset = None
alt_id = sys.argv[5]
new_summary_out_fh = open(sys.argv[6], "w")
allvar_mean_dp=None
try:
    allvar_mean_dp=int(float(str(sys.argv[7])))
except Exception as e:
    print(e,file=sys.stderr)
    allvar_mean_dp = -1

print(f"ARGS {sys.argv}", file=sys.stderr)
alnr=sys.argv[8]
ddup=sys.argv[9]
snv_caller=sys.argv[10]



cov_bin=None
if allvar_mean_dp >=0 and allvar_mean_dp < 1:
    cov_bin=0
elif allvar_mean_dp > 0 and allvar_mean_dp < 3:
    cov_bin=1
elif allvar_mean_dp >= 3 and allvar_mean_dp < 5:
    cov_bin=3
elif allvar_mean_dp >= 5 and allvar_mean_dp < 7:
    cov_bin=5
elif allvar_mean_dp >= 7 and allvar_mean_dp < 10:
    cov_bin=7
elif allvar_mean_dp >= 10 and allvar_mean_dp < 15:
    cov_bin=10
elif allvar_mean_dp >= 15 and allvar_mean_dp < 20:
    cov_bin=15
elif allvar_mean_dp >= 20 and allvar_mean_dp < 25:
    cov_bin=20
elif allvar_mean_dp >=25 and allvar_mean_dp < 30:
    cov_bin=25
elif allvar_mean_dp >=30 and allvar_mean_dp < 35:
    cov_bin=30
elif allvar_mean_dp >=35 and allvar_mean_dp < 40:
    cov_bin=35
elif allvar_mean_dp >=40 and allvar_mean_dp < 45:
    cov_bin=40
elif allvar_mean_dp >=45 and allvar_mean_dp < 50:
    cov_bin=45
elif allvar_mean_dp >= 50:
    cov_bin=50
else:
    cov_bin=-2

print(f"VARCOV: {allvar_mean_dp} -- COVBINIS: {cov_bin}", file=sys.stderr)

even_newer_summary = "{0}/snv_{2}_{1}_concordance.mqc.tsv".format(
    os.path.dirname(sys.argv[6]), cmp_footprint, sample
)

cmd = "cat {0} | awk -F'\t' 'BEGIN{{SUM=0}}{{ SUM+=$3-$2 }}END{{print SUM}}'".format(
    tgt_region_bed
)
tgt_region_size = float(os.popen(cmd).readline())


new_summary_out_fh.write(
    "Sample\tROI\tTN\tTP\tFP\tFN\tPrecision\tSensitivity-Recall\tSpecificity\tFDR\tFscore\tTgtRegionSize\tSubset\tAltID\tAllVarMeanDP\n"
)
ctr = 0
for i in summary_fh:
    line = i.lstrip(" ").rstrip()
    if ctr == 3:
        sl = re.split(r" +", line)
        threshold = sl[0]
        tp_baseline = float(sl[1])
        tp = float(sl[2])
        fp = float(sl[3])
        fn = float(sl[4])
        f_measure = float(sl[7])
        tn = float(tgt_region_size - (tp + fn))

        new_summary_out_fh.write(
            "{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}\t{8}\t{9}\t{10}\t{11}\t{12}\t{13}\t{14}".format(
                sample,
                cmp_footprint,
                tn,
                tp,
                fp,
                fn,
                tp / (tp + fp),
                tp / (tp + fn),
                tn / (tn + fp),
                fp / (tp + fp),
                f_measure,
                tgt_region_size,
                subset,
                alt_id,
                allvar_mean_dp
            )
        )
    ctr = 1 + ctr

def _proc_vcf(vcf_n):
    new_vcf_n = f"{vcf_n.replace('.','_')}_stripped.vcf.gz"
    ccmd = f" bcftools  annotate  -x INFO/datasets,INFO/platforms,INFO/callsetnames,INFO/platformnames,INFO/callable,INFO/datasetnames  --threads {cpus_div4} -O z -o {new_vcf_n} {vcf_n}; tabix -f {new_vcf_n}; "
    print(f"{ccmd}", file=sys.stderr)
    os.system(ccmd)
    return(new_vcf_n)

new_summary_out_fh.close()

tp_vcf = sys.argv[1].replace("summary.txt", "tp.vcf.gz")
tp_count = sys.argv[1].replace("summary.txt", "tp.count")
tp_cmd = "env python workflow/scripts/classify_var_by_type_size.py {0} {1} {2} {3} {4} {5}".format(
    _proc_vcf(tp_vcf), "TP", tgt_region_size, tp_count, sample, alt_id
)
print(tp_cmd, file=sys.stderr)
os.system(tp_cmd)

fp_vcf = sys.argv[1].replace("summary.txt", "fp.vcf.gz")
fp_count = sys.argv[1].replace("summary.txt", "fp.count")
fp_cmd = "env python workflow/scripts/classify_var_by_type_size.py {0} {1} {2} {3} {4} {5}".format(
    _proc_vcf(fp_vcf), "FP", tgt_region_size, fp_count, sample, alt_id
)
print(fp_cmd, file=sys.stderr)
os.system(fp_cmd)


fn_vcf = sys.argv[1].replace("summary.txt", "fn.vcf.gz")
fn_count = sys.argv[1].replace("summary.txt", "fn.count")
fn_cmd = "env python workflow/scripts/classify_var_by_type_size.py {0} {1} {2} {3} {4} {5}".format(
    _proc_vcf(fn_vcf), "FN", tgt_region_size, fn_count, sample, alt_id
)
print(fn_cmd, file=sys.stderr)
os.system(fn_cmd)

### Gather per-var type metrics, generate a more detailed view of the new_summary.txt
ds_var = {"TP": {}, "FP": {}, "FN": {}}

for cnt in [fn_count, fp_count, tp_count]:
    if os.path.exists(cnt):
        pass
    else:
        continue
    cnf_fh = open(cnt, "r")
    ctr = 0
    for c in cnf_fh:
        print(c, file=sys.stderr)
        c_sl = c.rstrip().split("\t")

        if ctr > 0:
            print(
                f"BBBB:{c_sl[0]}",file=sys.stderr
            )
            call_class = c_sl[1]
            print(f"XXXXX {c_sl} {c} {cnt}", file=sys.stderr)
            ds_var[call_class]["SNPts"] = int(c_sl[2])
            ds_var[call_class]["SNPtv"] = int(c_sl[3])
            ds_var[call_class]["INS_50"] = int(c_sl[4])
            ds_var[call_class]["INS_gt50"] = int(c_sl[5])
            ds_var[call_class]["DEL_50"] = int(c_sl[6])
            ds_var[call_class]["DEL_gt50"] = int(c_sl[7])
            ds_var[call_class]["Indel_50"] = int(c_sl[8])
            ds_var[call_class]["Indel_gt50"] = int(c_sl[9])
            ds_var[call_class]["tgtRegionSize"] = float(c_sl[10])

        elif ctr == 0:
            print("AAA", file=sys.stderr)

        else:
            print(c, file=sys.stderr)
            raise

        ctr += 1


print(ds_var, file=sys.stderr)


def _safe_div(num, den):
    try:
        den = float(den)
        if den == 0:
            return None
        return float(num) / den
    except Exception:
        return None


def _empty_none(value):
    return "" if value is None else value


variant_classes = [
    "SNPts",
    "SNPtv",
    "INS_50",
    "INS_gt50",
    "DEL_50",
    "DEL_gt50",
    "Indel_50",
    "Indel_gt50",
]
for call_class_data in ds_var.values():
    for variant_class in call_class_data:
        if variant_class != "tgtRegionSize" and variant_class not in variant_classes:
            variant_classes.append(variant_class)

rows = []
for variant_class in variant_classes:
    tp = float(ds_var.get("TP", {}).get(variant_class, 0.0) or 0.0)
    fn = float(ds_var.get("FN", {}).get(variant_class, 0.0) or 0.0)
    fp = float(ds_var.get("FP", {}).get(variant_class, 0.0) or 0.0)
    try:
        target_size = float(ds_var.get("TP", {}).get("tgtRegionSize"))
    except Exception:
        target_size = None
    tn = None if target_size is None else target_size - (tp + fn)
    rows.append(
        {
            "VariantClass": variant_class,
            "TgtRegionSize": target_size,
            "TN": tn,
            "FN": fn,
            "TP": tp,
            "FP": fp,
        }
    )

all_tp = sum(float(row["TP"]) for row in rows)
all_fn = sum(float(row["FN"]) for row in rows)
all_fp = sum(float(row["FP"]) for row in rows)
rows.append(
    {
        "VariantClass": "All",
        "TgtRegionSize": tgt_region_size,
        "TN": tgt_region_size - (all_tp + all_fn),
        "FN": all_fn,
        "TP": all_tp,
        "FP": all_fp,
    }
)

for row in rows:
    precision = _safe_div(row["TP"], row["TP"] + row["FP"])
    sensitivity = _safe_div(row["TP"], row["TP"] + row["FN"])
    row["Precision"] = precision
    row["Sensitivity-Recall"] = sensitivity
    row["Specificity"] = _safe_div(row["TN"], row["TN"] + row["FP"])
    row["FDR"] = _safe_div(row["FP"], row["TP"] + row["FP"])
    row["PPV"] = None if row["FDR"] is None else 1.0 - row["FDR"]
    if precision is None or sensitivity is None or (precision + sensitivity) == 0:
        row["Fscore"] = None
    else:
        row["Fscore"] = 2.0 * ((precision * sensitivity) / (precision + sensitivity))

stage_sample = f"{sample}.{alnr}.{ddup}.{snv_caller}"
print_cols = [
    'Sample',
    'VariantClass',
    'InputSample',
    'TgtRegionSize',
    'TN',
    'FN',
    'TP',
    'FP',
    'Fscore',
    'Sensitivity-Recall',
    'Specificity',
    'FDR',
    'PPV',
    'Precision',
    'AltId',
    'ROI',
    'AllVarMeanDP',
    'CovBin',
    'Aligner',
    'Deduper',
    'SNVCaller',
]
for row in rows:
    variant_class = row["VariantClass"]
    row["Sample"] = f"{stage_sample}.{variant_class}"
    row["InputSample"] = sample
    row["AltId"] = alt_id
    row["ROI"] = cmp_footprint
    row["Subset"] = subset
    row["AllVarMeanDP"] = allvar_mean_dp
    row["CovBin"] = cov_bin
    row["Aligner"] = alnr
    row["Deduper"] = ddup
    row["SNVCaller"] = snv_caller

with open(even_newer_summary, "w", newline="") as out_fh:
    writer = csv.DictWriter(
        out_fh,
        fieldnames=print_cols,
        delimiter="\t",
        extrasaction="ignore",
    )
    writer.writeheader()
    for row in rows:
        writer.writerow({key: _empty_none(row.get(key)) for key in print_cols})
