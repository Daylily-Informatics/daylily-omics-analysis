#!/usr/bin/env python3
import re
import glob
import math
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

BASELINE_LABEL = "ILMN+sbwa+gatk"
COV_BIN = 35  # your internal “~30x” bin

# Choose a small, interpretable GQV vector (ROI, VariantClass)
DIMS = [
    ("hg38", "All"),
    ("giabHC", "All"),
    ("clinvar_genes", "All"),
    ("giabHC", "SNPtv"),
    ("hg38", "Indel_50"),
    ("clinvar_genes", "Indel_50"),
]

ALIGNER_DISPLAY = {"bwa2a": "bwa2", "sent": "sbwa"}
CALLER_DISPLAY = {
    "sentd": "dnascope",
    "sentdont": "dnascope-ont",
    "sentdpb": "dnascope-pb",
    "sentdug": "dnascope-ug",
    "sentdhio": "dnascope-hio",
    "sentdhuo": "dnascope-huo",
    "deep19r": "dv-roche",
}

EXCLUDE_RULES = {"alignstats_smmary_compile", "alignstats_summary", "dirsetup"}
EXCLUDE_SUFFIXES = (".concordance",)

def make_label(row):
    tg = str(row.get("TestGroup", ""))
    readlen = row.get("ReadLengthBP", "")
    pri = row["PrimarySeqPlatform"]
    sec = row.get("SecondarySeqPlatform", "")
    aligner = ALIGNER_DISPLAY.get(row["Aligner"], row["Aligner"])
    caller = CALLER_DISPLAY.get(row["SNVCaller"], row["SNVCaller"])

    if tg == "ilmn_read_trim" and str(readlen).strip():
        rl = int(float(readlen))
        return f"ILMN-sbwa-dnascope-{rl}paired"

    if isinstance(sec, str) and sec.strip():
        sec_meas = row.get("Secondary_MeasuredMeanCov", np.nan)
        try:
            sec_meas = float(sec_meas)
        except Exception:
            return None
        if not np.isfinite(sec_meas) or sec_meas == 0.0:
            return None
        sec_meas = round(sec_meas, 1)
        return f"{pri}+{sec}+{aligner}+{caller}+{sec_meas}x"

    return f"{pri}+{aligner}+{caller}"

def tech_class(row):
    sec = row.get("SecondarySeqPlatform", "")
    if isinstance(sec, str) and sec.strip():
        return "Hybrid"
    pri = row["PrimarySeqPlatform"]
    if pri in {"ONT", "PacBio"}:
        return "LR"
    return "SR"

def classify_rule(rule, caller_tokens):
    parts = str(rule).split(".")
    aligner = parts[0]
    caller = None
    for p in parts[1:]:
        base = re.sub(r"(\d+(-\d+)?)$", "", p).rstrip("-")
        base = re.sub(r"\d+$", "", base)
        if p in caller_tokens:
            caller = p
            break
        if base in caller_tokens:
            caller = base
            break
    return aligner, caller

def main():
    cc = pd.read_csv("consolidated_concordance.tsv", sep="\t")
    cc = cc[~cc["SNVCaller"].isin(["clair3", "oct"])].copy()
    cc = cc[cc["PrimaryCoverageBin"] == COV_BIN].copy()
    cc["label"] = cc.apply(make_label, axis=1)
    cc = cc[cc["label"].notna()].copy()

    # Build quality vector table (one row per label, one column per dim)
    pivot = cc.pivot_table(
        index="label",
        columns=["ROI", "VariantClass"],
        values="Fscore",
        aggfunc="first",
    )

    missing_dims = [d for d in DIMS if d not in pivot.columns]
    if missing_dims:
        raise SystemExit(f"Missing dims in concordance table: {missing_dims}")

    q = pivot[DIMS].dropna(axis=0, how="any")

    if BASELINE_LABEL not in q.index:
        raise SystemExit(f"Baseline label not found: {BASELINE_LABEL}")

    baseline = q.loc[BASELINE_LABEL].values.astype(float)
    X = q.values.astype(float)

    # Shortfall-only distance (RMS F-score loss vs baseline)
    shortfall = np.maximum(0.0, baseline - X)
    dist = np.sqrt((shortfall ** 2).mean(axis=1))
    dist = pd.Series(dist, index=q.index, name="gqv_shortfall_rms")

    # Metadata for joining to benchmarks: use ROI=hg38, VariantClass=All rows
    meta = cc[(cc["ROI"] == "hg38") & (cc["VariantClass"] == "All")].copy()
    meta = meta.sort_values(["label", "TestGroup", "Sample"]).drop_duplicates(subset=["label"])
    meta = meta[meta["label"].isin(q.index)].copy()
    meta["sample_base"] = meta["Sample"].astype(str).str.rstrip(".")
    meta["tech"] = meta.apply(tech_class, axis=1)

    # Benchmarks: read all benchmarks_summary.tsv under current dir
    bench_files = glob.glob("**/benchmarks_summary.tsv", recursive=True)
    if not bench_files:
        raise SystemExit("No benchmarks_summary.tsv files found under current directory.")

    caller_tokens = set(cc["SNVCaller"].dropna().unique().tolist())
    caller_tokens |= {"oct", "dragen"}  # if present in rule names

    bench_rows = []
    for path in bench_files:
        tg = path.split("/")[0]
        b = pd.read_csv(path, sep="\t")
        b = b[~b["sample"].astype(str).str.startswith("all")].copy()
        b = b[~b["rule"].isin(EXCLUDE_RULES)].copy()
        for suf in EXCLUDE_SUFFIXES:
            b = b[~b["rule"].astype(str).str.endswith(suf)].copy()

        b["sample_base"] = b["sample"].astype(str).str.rstrip(".")
        b["task_cost"] = pd.to_numeric(b["task_cost"], errors="coerce").fillna(0.0)
        b["s"] = pd.to_numeric(b["s"], errors="coerce").fillna(0.0)

        cls = b["rule"].apply(lambda r: classify_rule(r, caller_tokens))
        b["aligner_token"] = cls.apply(lambda x: x[0])
        b["caller_token"] = cls.apply(lambda x: x[1])
        b["TestGroup"] = tg

        bench_rows.append(b[["TestGroup", "sample_base", "aligner_token", "caller_token", "task_cost", "s"]])

    bench = pd.concat(bench_rows, ignore_index=True)

    def pipeline_cost_time(r):
        df = bench[(bench["TestGroup"] == r["TestGroup"]) & (bench["sample_base"] == r["sample_base"])].copy()
        if df.empty:
            return pd.Series({"cost_usd": np.nan, "time_s": np.nan})

        hybrid = (isinstance(r.get("SecondarySeqPlatform", ""), str) and str(r["SecondarySeqPlatform"]).strip())
        raw_aligner = r["Aligner"]
        raw_caller = r["SNVCaller"]

        # If not hybrid, restrict to the pipeline’s aligner token to avoid multi-aligner overcount
        if not hybrid and isinstance(raw_aligner, str) and raw_aligner.strip():
            df = df[df["aligner_token"] == raw_aligner].copy()

        df = df[(df["caller_token"].isna()) | (df["caller_token"] == raw_caller)].copy()
        if df.empty:
            return pd.Series({"cost_usd": np.nan, "time_s": np.nan})

        return pd.Series({"cost_usd": df["task_cost"].sum(), "time_s": df["s"].sum()})

    ct = meta.apply(pipeline_cost_time, axis=1)
    meta = pd.concat([meta.reset_index(drop=True), ct], axis=1)
    meta["tat_h"] = meta["time_s"] / 3600.0

    out = meta.set_index("label").join(dist, how="inner")
    out = out.dropna(subset=["cost_usd", "tat_h", "gqv_shortfall_rms"]).copy()
    out = out.sort_values(["cost_usd", "gqv_shortfall_rms"])

    out.to_csv("pareto_points.tsv", sep="\t", index=True)

    # Matplotlib plot
    marker_map = {"SR": "o", "LR": "^", "Hybrid": "s"}

    fig, ax = plt.subplots(figsize=(9, 6))
    for tech, grp in out.groupby("tech"):
        ax.scatter(
            grp["cost_usd"],
            grp["gqv_shortfall_rms"],
            c=grp["tat_h"],          # color by TAT proxy, default cmap
            marker=marker_map.get(tech, "o"),
            s=60,
            label=tech,
        )

    cbar = fig.colorbar(ax.collections[0], ax=ax)
    cbar.set_label("TAT proxy (hours)")

    ax.set_xlabel("Pipeline cost (USD, compute-only proxy)")
    ax.set_ylabel("GQV shortfall vs baseline (RMS F-score loss)")
    ax.set_title(f"Cost vs GQV shortfall at ~30x (bin {COV_BIN})")
    ax.grid(True, alpha=0.2)
    ax.legend(title="Tech")

    fig.tight_layout()
    fig.savefig("pareto_cost_gqv.png", dpi=200)
    fig.savefig("pareto_cost_gqv.svg")

    print("Wrote: pareto_points.tsv, pareto_cost_gqv.png, pareto_cost_gqv.svg")

if __name__ == "__main__":
    main()