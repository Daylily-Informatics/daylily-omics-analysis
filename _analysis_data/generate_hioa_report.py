#!/usr/bin/env python3
"""Generate HIOa hybrid workflow summary report from gathered JSON data.

Reads: _analysis_data/hioa_data.json
Outputs:
  _analysis_data/HIOa_hybrid_summary.tsv
  _analysis_data/HIOa_hybrid_summary.md
"""

import csv
import json
import os
import sys
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent

# Units currently running on slurm (snapshot from 2026-02-18 ~18:30 UTC)
RUNNING_UNITS_PARTIAL = [
    "SR10x-ONT10x", "SR15x-ONT3x", "SR15x-ONT7x", "SR30x-ONT10x",
    "SR3x-ONT3x", "SR40x-ONT10x", "SR40x-ONT7x", "SR5x-ONT1x",
    "SR5x-ONT3x", "SR7x-ONT10x", "SR7x-ONT1x", "SR7x-ONT3x",
]

SNP_CLASSES = ["SNPts", "SNPtv", "DEL_50", "INS_50", "Indel_50"]
STAGE_MAP = {
    "mrkdup": "alignment",
    "alignstats": "alignstats",
    "sentdhio": "variant_calling",
    "concordance": "concordance",
}

def classify_stage(rule: str) -> str:
    for key, stage in STAGE_MAP.items():
        if key in rule:
            return stage
    return "other"

def safe_div(a, b):
    return a / b if b else 0

# --- Load data ---
with open(BASE / "hioa_data.json") as f:
    data = json.load(f)

units = data["units"]

# --- Refine status using slurm running list ---
for u in units:
    short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
    if u["status"] == "Failed/Pending" and short in RUNNING_UNITS_PARTIAL:
        u["status"] = "In Progress"
    elif u["status"] == "In Progress":
        if short in RUNNING_UNITS_PARTIAL:
            u["status"] = "In Progress"
    # If no failure reason and still failed, mark generic
    if u["status"] == "Failed/Pending" and not u["failure_reason"]:
        u["failure_reason"] = "sentdhio_snv failed (no diagnostic output)"

# Sort by SR coverage then ONT coverage
units.sort(key=lambda u: (u["sr_cov"], u["ont_cov"]))

# --- Build TSV rows ---
tsv_header = [
    "Unit", "SR_Cov", "ONT_Cov", "Status", "Failure_Reason",
    "WgsCoverageMean", "WgsCoverageMedian",
]
for cls in SNP_CLASSES:
    tsv_header.extend([f"{cls}_Fscore", f"{cls}_Precision", f"{cls}_Recall",
                       f"{cls}_FN", f"{cls}_FP"])
tsv_header.extend([
    "Total_Wall_Min", "Total_Cost_USD",
    "Alignment_Cost", "VariantCalling_Cost", "Concordance_Cost", "Alignstats_Cost",
    "Alignment_Wall_Min", "VariantCalling_Wall_Min", "Concordance_Wall_Min", "Alignstats_Wall_Min",
])

tsv_rows = []
for u in units:
    short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
    row = {
        "Unit": short,
        "SR_Cov": u["sr_cov"],
        "ONT_Cov": u["ont_cov"],
        "Status": u["status"],
        "Failure_Reason": u["failure_reason"],
        "WgsCoverageMean": f"{u['alignstats'].get('WgsCoverageMean', ''):.2f}" if u["alignstats"] else "",
        "WgsCoverageMedian": f"{u['alignstats'].get('WgsCoverageMedian', ''):.0f}" if u["alignstats"] else "",
    }
    # Concordance metrics
    for cls in SNP_CLASSES:
        if cls in u.get("concordance", {}):
            c = u["concordance"][cls]
            row[f"{cls}_Fscore"] = f"{c['Fscore']:.6f}"
            row[f"{cls}_Precision"] = f"{c['Precision']:.6f}"
            row[f"{cls}_Recall"] = f"{c['Recall']:.6f}"
            row[f"{cls}_FN"] = str(c["FN"])
            row[f"{cls}_FP"] = str(c["FP"])
        else:
            for suffix in ("Fscore", "Precision", "Recall", "FN", "FP"):
                row[f"{cls}_{suffix}"] = ""

    # Benchmarks aggregation
    stage_cost = {}
    stage_wall = {}
    for b in u.get("benchmarks", []):
        stage = classify_stage(b["rule"])
        stage_cost[stage] = stage_cost.get(stage, 0) + b["task_cost"]
        stage_wall[stage] = stage_wall.get(stage, 0) + b["wall_sec"]
    total_cost = sum(stage_cost.values())
    total_wall = sum(stage_wall.values())
    row["Total_Wall_Min"] = f"{total_wall / 60:.1f}" if total_wall else ""
    row["Total_Cost_USD"] = f"{total_cost:.4f}" if total_cost else ""
    for stage_key, col_prefix in [("alignment", "Alignment"), ("variant_calling", "VariantCalling"),
                                   ("concordance", "Concordance"), ("alignstats", "Alignstats")]:
        row[f"{col_prefix}_Cost"] = f"{stage_cost.get(stage_key, 0):.4f}" if stage_cost.get(stage_key) else ""
        wall = stage_wall.get(stage_key, 0)
        row[f"{col_prefix}_Wall_Min"] = f"{wall / 60:.1f}" if wall else ""

    tsv_rows.append(row)

# --- Write TSV ---
tsv_path = BASE / "HIOa_hybrid_summary.tsv"
with open(tsv_path, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=tsv_header, delimiter="\t")
    writer.writeheader()
    for row in tsv_rows:
        writer.writerow(row)
print(f"TSV saved: {tsv_path} ({len(tsv_rows)} rows)")

# --- Generate Markdown ---
md_path = BASE / "HIOa_hybrid_summary.md"
complete = [u for u in units if u["status"] == "Complete"]
in_prog = [u for u in units if u["status"] == "In Progress"]
failed = [u for u in units if u["status"] == "Failed/Pending"]

with open(md_path, "w") as md:
    md.write("# HIOa Hybrid ILMN+ONT Workflow Summary Report\n\n")
    md.write(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
    md.write(f"**Genome Build**: hg38_broad\n\n")
    md.write(f"**Sample**: HG003 (Ashkenazi Jewish Father)\n\n")
    md.write(f"**Matrix**: 9 ILMN coverages (1x–40x) × 7 ONT coverages (1x–30x) = 63 units\n\n")
    md.write(f"**Workflow Config**: `-T 1 -j 20 -k -p` (1 retry, 20 concurrent jobs)\n\n")

    # Status summary
    md.write("## Unit Status Summary\n\n")
    md.write(f"| Status | Count |\n|---|---|\n")
    md.write(f"| ✅ Complete | {len(complete)} |\n")
    md.write(f"| 🔄 In Progress | {len(in_prog)} |\n")
    md.write(f"| ❌ Failed/Pending | {len(failed)} |\n")
    md.write(f"| **Total** | **{len(units)}** |\n\n")

    # Status matrix (SR rows × ONT cols)
    sr_covs = sorted(set(u["sr_cov"] for u in units))
    ont_covs = sorted(set(u["ont_cov"] for u in units))
    status_map = {(u["sr_cov"], u["ont_cov"]): u["status"] for u in units}
    status_icons = {"Complete": "✅", "In Progress": "🔄", "Failed/Pending": "❌"}

    md.write("### Status Matrix (SR↓ × ONT→)\n\n")
    md.write("| SR \\ ONT | " + " | ".join(f"{c}x" for c in ont_covs) + " |\n")
    md.write("|---|" + "|".join(["---"] * len(ont_covs)) + "|\n")
    for sr in sr_covs:
        cells = []
        for ont in ont_covs:
            s = status_map.get((sr, ont), "?")
            cells.append(status_icons.get(s, "?"))
        md.write(f"| **{sr}x** | " + " | ".join(cells) + " |\n")
    md.write("\n")

    # Concordance table (completed units only)
    md.write("## Concordance Metrics (giabHC footprint, completed units)\n\n")
    if complete:
        md.write("### F-scores by Variant Class\n\n")
        md.write("| Unit | SNPts | SNPtv | DEL_50 | INS_50 | Indel_50 |\n")
        md.write("|---|---|---|---|---|---|\n")
        for u in sorted(complete, key=lambda x: (x["sr_cov"], x["ont_cov"])):
            short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
            vals = []
            for cls in SNP_CLASSES:
                if cls in u["concordance"]:
                    vals.append(f"{u['concordance'][cls]['Fscore']:.4f}")
                else:
                    vals.append("—")
            md.write(f"| {short} | " + " | ".join(vals) + " |\n")
        md.write("\n")

        # Detailed concordance: Precision, Recall, FN, FP
        md.write("### Detailed Metrics (Precision / Recall / FN / FP)\n\n")
        for cls in SNP_CLASSES:
            md.write(f"#### {cls}\n\n")
            md.write("| Unit | Fscore | Precision | Recall | FN | FP |\n")
            md.write("|---|---|---|---|---|---|\n")
            for u in sorted(complete, key=lambda x: (x["sr_cov"], x["ont_cov"])):
                short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
                if cls in u["concordance"]:
                    c = u["concordance"][cls]
                    md.write(f"| {short} | {c['Fscore']:.4f} | {c['Precision']:.4f} | "
                             f"{c['Recall']:.4f} | {c['FN']:,} | {c['FP']:,} |\n")
            md.write("\n")

        # Summary statistics
        md.write("### Summary Statistics (across completed units)\n\n")
        md.write("| Variant Class | Mean Fscore | Median Fscore | Min Fscore | Max Fscore |\n")
        md.write("|---|---|---|---|---|\n")
        for cls in SNP_CLASSES:
            fscores = [u["concordance"][cls]["Fscore"] for u in complete if cls in u["concordance"]]
            if fscores:
                fscores.sort()
                mean_f = sum(fscores) / len(fscores)
                median_f = fscores[len(fscores) // 2]
                md.write(f"| {cls} | {mean_f:.4f} | {median_f:.4f} | {min(fscores):.4f} | {max(fscores):.4f} |\n")
        md.write("\n")

    # Coverage metrics
    md.write("## Coverage Metrics (all units)\n\n")
    md.write("| Unit | WgsCoverageMean | WgsCoverageMedian | Status |\n")
    md.write("|---|---|---|---|\n")
    for u in units:
        short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
        if u["alignstats"]:
            md.write(f"| {short} | {u['alignstats']['WgsCoverageMean']:.2f} | "
                     f"{u['alignstats']['WgsCoverageMedian']:.0f} | {status_icons.get(u['status'], '?')} |\n")
    md.write("\n")

    # Compute benchmarks
    md.write("## Compute Benchmarks\n\n")
    total_cost_all = 0
    total_wall_all = 0
    bench_units = []
    for u in units:
        if not u["benchmarks"]:
            continue
        stage_cost = {}
        stage_wall = {}
        for b in u["benchmarks"]:
            stage = classify_stage(b["rule"])
            stage_cost[stage] = stage_cost.get(stage, 0) + b["task_cost"]
            stage_wall[stage] = stage_wall.get(stage, 0) + b["wall_sec"]
        tc = sum(stage_cost.values())
        tw = sum(stage_wall.values())
        total_cost_all += tc
        total_wall_all += tw
        bench_units.append((u, tc, tw, stage_cost, stage_wall))

    md.write(f"**Total cost across all units**: ${total_cost_all:.2f}\n\n")
    md.write(f"**Total wall time across all units**: {total_wall_all / 3600:.1f} hours\n\n")

    md.write("### Per-Unit Cost & Runtime (completed units)\n\n")
    md.write("| Unit | Status | Total Cost | Total Wall (min) | VC Cost | VC Wall (min) | Conc Cost | Conc Wall (min) |\n")
    md.write("|---|---|---|---|---|---|---|---|\n")
    for u, tc, tw, sc, sw in bench_units:
        short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
        vc_cost = sc.get("variant_calling", 0)
        vc_wall = sw.get("variant_calling", 0) / 60
        cc_cost = sc.get("concordance", 0)
        cc_wall = sw.get("concordance", 0) / 60
        md.write(f"| {short} | {status_icons.get(u['status'], '?')} | ${tc:.2f} | {tw/60:.1f} | "
                 f"${vc_cost:.2f} | {vc_wall:.1f} | ${cc_cost:.2f} | {cc_wall:.1f} |\n")
    md.write("\n")

    # Failed units
    md.write("## Failed Units\n\n")
    if failed:
        md.write("| Unit | SR Cov | ONT Cov | Failure Reason |\n")
        md.write("|---|---|---|---|\n")
        for u in sorted(failed, key=lambda x: (x["sr_cov"], x["ont_cov"])):
            short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
            md.write(f"| {short} | {u['sr_cov']}x | {u['ont_cov']}x | {u['failure_reason']} |\n")
    else:
        md.write("No failed units.\n")
    md.write("\n")

    # In-progress units
    md.write("## In-Progress Units\n\n")
    if in_prog:
        md.write("| Unit | SR Cov | ONT Cov |\n")
        md.write("|---|---|---|\n")
        for u in sorted(in_prog, key=lambda x: (x["sr_cov"], x["ont_cov"])):
            short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
            md.write(f"| {short} | {u['sr_cov']}x | {u['ont_cov']}x |\n")
    else:
        md.write("No in-progress units.\n")
    md.write("\n")

print(f"Markdown saved: {md_path}")
print(f"\nSummary: {len(complete)} complete, {len(in_prog)} in progress, {len(failed)} failed")

