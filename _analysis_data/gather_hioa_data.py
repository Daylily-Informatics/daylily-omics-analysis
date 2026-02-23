#!/usr/bin/env python3
"""Gather all HIOa hybrid workflow data from headnode into JSON for local processing.

Run on the headnode at:
  /fsx/analysis_results/ubuntu/agbt_hio_expanded/daylily-omics-analysis/

Outputs: /tmp/hioa_data.json
"""

import csv
import glob
import json
import os
import re
import sys

BASE = "/fsx/analysis_results/ubuntu/agbt_hio_expanded/daylily-omics-analysis"
RESULTS = os.path.join(BASE, "results/day/hg38_broad")
UNIT_RE = re.compile(r"(HIOa-HG003-SR(\d+)x-ONT(\d+)x-\d+-D0-PF-ILMN-NOVASEQ)")

# 1. Enumerate all 63 units
units = {}
for d in sorted(glob.glob(os.path.join(RESULTS, "HIOa-HG003-*"))):
    name = os.path.basename(d)
    m = UNIT_RE.match(name)
    if not m:
        continue
    sr_cov = int(m.group(2))
    ont_cov = int(m.group(3))
    units[name] = {"unit": name, "sr_cov": sr_cov, "ont_cov": ont_cov,
                   "status": "Unknown", "failure_reason": "",
                   "concordance": {}, "concordance_clinvar": {}, "concordance_hg38": {},
                   "alignstats": {}, "benchmarks": []}

# 2. Determine status per unit
for name, info in units.items():
    unit_dir = os.path.join(RESULTS, name)
    conc_done = glob.glob(os.path.join(unit_dir, "align/ont/na/snv/sentdhio/concordance/concordance.done")) or \
                glob.glob(os.path.join(unit_dir, "align/ont/na/snv/sentdhio/concordance/_giabHC/summary.txt"))
    vcf_files = glob.glob(os.path.join(unit_dir, "align/ont/na/snv/sentdhio/*.sentdhio_snv.vcf.gz"))
    bench_files = glob.glob(os.path.join(unit_dir, "benchmarks/*.sentdhio*.bench.tsv"))
    if conc_done:
        info["status"] = "Complete"
    elif vcf_files:
        info["status"] = "VCF_Done"
    elif bench_files:
        info["status"] = "In Progress"
    else:
        info["status"] = "Failed/Pending"

# 3. Read concordance mqc.tsv for all footprints
def read_concordance_mqc(mqc_path):
    """Parse a concordance mqc.tsv into a dict keyed by VariantClass."""
    result = {}
    if not os.path.exists(mqc_path):
        return result
    with open(mqc_path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            cls = row["VariantClass"]
            try:
                fscore = float(row["Fscore"]) if row.get("Fscore", "").strip() else 0.0
                precision = float(row["Precision"]) if row.get("Precision", "").strip() else 0.0
                recall = float(row["Sensitivity-Recall"]) if row.get("Sensitivity-Recall", "").strip() else 0.0
                fn = int(float(row["FN"])) if row.get("FN", "").strip() else 0
                fp = int(float(row["FP"])) if row.get("FP", "").strip() else 0
                tp = int(float(row["TP"])) if row.get("TP", "").strip() else 0
            except (ValueError, TypeError):
                continue
            result[cls] = {
                "Fscore": fscore, "Precision": precision, "Recall": recall,
                "FN": fn, "FP": fp, "TP": tp,
            }
    return result

FOOTPRINTS = [
    ("concordance",         "_giabHC",        "giabHC"),
    ("concordance_clinvar", "_clinvar_genes",  "clinvar_genes"),
    ("concordance_hg38",    "_hg38",           "hg38"),
]

for name, info in units.items():
    for field_key, dir_name, file_tag in FOOTPRINTS:
        mqc_path = os.path.join(RESULTS, name,
            f"align/ont/na/snv/sentdhio/concordance/{dir_name}",
            f"snv_{name}_{file_tag}_concordance.mqc.tsv")
        info[field_key] = read_concordance_mqc(mqc_path)

# 4. Read alignstats combo TSV
alignstats_path = os.path.join(RESULTS, "other_reports/alignstats_combo_mqc.tsv")
if os.path.exists(alignstats_path):
    with open(alignstats_path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            sample = row["sample"]  # e.g. HIOa-HG003-SR10x-ONT10x-31-D0-PF-ILMN-NOVASEQ.ont
            base = sample.rsplit(".", 1)[0]
            if base in units:
                units[base]["alignstats"] = {
                    "WgsCoverageMean": float(row.get("WgsCoverageMean", 0)),
                    "WgsCoverageMedian": float(row.get("WgsCoverageMedian", 0)),
                    "aligner": row.get("aligner", ""),
                }

# 5. Read all benchmark files per unit
for name, info in units.items():
    bench_dir = os.path.join(RESULTS, name, "benchmarks")
    if not os.path.isdir(bench_dir):
        continue
    for bf in sorted(glob.glob(os.path.join(bench_dir, "*.bench.tsv"))):
        rule_name = os.path.basename(bf).replace(f"{name}.ont.na.", "").replace(".bench.tsv", "")
        try:
            with open(bf) as f:
                reader = csv.DictReader(f, delimiter="\t")
                for row in reader:
                    def safe_float(v, default=0.0):
                        try:
                            return float(v)
                        except (ValueError, TypeError):
                            return default
                    info["benchmarks"].append({
                        "rule": rule_name,
                        "wall_sec": safe_float(row.get("s", 0)),
                        "max_rss": safe_float(row.get("max_rss", 0)),
                        "task_cost": safe_float(row.get("task_cost", 0)),
                        "cpu_efficiency": safe_float(row.get("cpu_efficiency", 0)),
                        "instance_type": row.get("instance_type", ""),
                        "snakemake_threads": int(safe_float(row.get("snakemake_threads", 0))),
                    })
        except Exception as e:
            print(f"WARN: Error reading {bf}: {e}", file=sys.stderr)

# 6. Check snakemake log for failure reasons
log_path = os.path.join(BASE, ".snakemake/log/2026-02-18T015205.040010.snakemake.log")
if os.path.exists(log_path):
    with open(log_path) as f:
        log_text = f.read()
    # Find failed rules per unit
    for name, info in units.items():
        if info["status"] in ("Complete", "VCF_Done"):
            continue
        short = name.split("-41-")[0] if "-41-" in name else name
        # Count error mentions
        err_count = log_text.count(f"Error in rule sentdhio_snv") 
        if name in log_text:
            idx = log_text.find(name)
            ctx = log_text[max(0, idx-200):idx+200]
            if "CANCELLED" in ctx:
                info["failure_reason"] = "Spot reclamation (CANCELLED)"
            elif "rm: cannot remove" in ctx:
                info["failure_reason"] = "TMPDIR race condition"
            elif "Error" in ctx or "error" in ctx:
                info["failure_reason"] = "sentdhio_snv failure (0-byte log)"

# 7. Check slurm logs for more detail
for name, info in units.items():
    if info["status"] not in ("Failed/Pending",) or info["failure_reason"]:
        continue
    slurm_err = glob.glob(os.path.join(BASE, f"logs/slurm/sentdhio_snv/sentdhio_snv.{name}.*.err"))
    for ef in slurm_err:
        try:
            with open(ef) as f:
                content = f.read()
            if "CANCELLED" in content:
                info["failure_reason"] = "Spot reclamation"
            elif "rm: cannot remove" in content:
                info["failure_reason"] = "TMPDIR race condition"
            elif len(content.strip()) == 0:
                info["failure_reason"] = "Empty error log (likely license/crash)"
        except:
            pass

# Output
data = {"units": list(units.values()), "total_units": len(units)}
with open("/tmp/hioa_data.json", "w") as f:
    json.dump(data, f, indent=2)
print(f"Wrote {len(units)} units to /tmp/hioa_data.json")

