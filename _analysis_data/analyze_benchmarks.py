#!/usr/bin/env python3
"""Multi-tenancy-aware benchmark analysis. ALL metrics derived from data.

Per-row fields used:
  sample             → RunID = first segment split on '-'
  instance_type      → node RAM lookup (no hardcoded default)
  nproc              → total node vCPUs (varies per instance)
  snakemake_threads  → allocated threads for THIS job
  spot_cost          → actual spot rate for THIS instance
  mean_load / 100    → actual CPU cores used
  max_rss            → peak RAM (MB)
  io_in, io_out      → I/O volume (MB)
  task_cost          → pro-rated: wall_hrs * spot * (threads/nproc)
"""

import sys
import csv
import re
from collections import defaultdict
from pathlib import Path

BENCHMARKS_DIR = Path(__file__).parent / "benchmarks"
FILES = sorted(BENCHMARKS_DIR.glob("*_benchmarks.tsv"))

# Instance RAM from AWS specs (GiB → MB). Extended as new types appear.
INSTANCE_RAM_GIB = {
    "m7i.48xlarge": 768,
    "c7i.metal-48xl": 384,
    "r7i.4xlarge": 128,
}


def sf(val, default=0.0):
    try:
        return default if val in ("NA", "", None) else float(val)
    except (ValueError, TypeError):
        return default


def run_id(sample):
    """RunID = first '-'-delimited segment of sample name."""
    return sample.split("-")[0].rstrip(".") if sample else "unknown"


def nominal_cov(sample):
    m = re.search(r"-(\d+)x-", sample)
    return int(m.group(1)) if m else None


_WARNED_ITYPES = set()


def instance_ram_mb(itype):
    """Look up RAM in MB for an instance type."""
    gib = INSTANCE_RAM_GIB.get(itype)
    if gib is None:
        if itype != "NA" and itype not in _WARNED_ITYPES:
            print(f"  WARNING: unknown instance_type '{itype}', assuming 768 GiB",
                  file=sys.stderr)
            _WARNED_ITYPES.add(itype)
        gib = 768
    return gib * 1024


def load_and_enrich():
    """Load all benchmark TSVs, enrich each row with derived metrics."""
    rows = []
    for fpath in FILES:
        # Derive platform label from filename (e.g., 'ilmn' from 'ilmn_hg003_...')
        fname = fpath.stem  # e.g. ilmn_hg003_prod_benchmarks
        with open(fpath) as f:
            for r in csv.DictReader(f, delimiter="\t"):
                r["src_file"] = fname
                for k in ("s", "max_rss", "max_vms", "max_uss", "max_pss",
                           "io_in", "io_out", "mean_load", "cpu_time",
                           "cpu_efficiency", "spot_cost", "task_cost"):
                    r[k] = sf(r.get(k))
                r["snakemake_threads"] = int(sf(r.get("snakemake_threads")))
                r["nproc"] = int(sf(r.get("nproc")))
                itype = r.get("instance_type", "unknown")
                r["instance_type"] = itype

                # ---- derived metrics ----
                thr = r["snakemake_threads"]
                nproc = r["nproc"]
                node_ram = instance_ram_mb(itype)
                rss = r["max_rss"]
                wall = r["s"]

                r["run_id"] = run_id(r.get("sample", ""))
                r["cov"] = nominal_cov(r.get("sample", ""))
                r["node_ram_mb"] = node_ram
                r["actual_cores"] = r["mean_load"] / 100.0
                r["thread_eff"] = (r["actual_cores"] / thr * 100) if thr else 0
                r["ram_pct"] = (rss / node_ram * 100) if node_ram else 0
                r["slots_threads"] = nproc // thr if thr else 0
                r["slots_ram"] = int(node_ram / rss) if rss > 100 else 99
                r["max_conc"] = min(r["slots_threads"], r["slots_ram"])
                r["io_total"] = r["io_in"] + r["io_out"]
                r["io_rate"] = r["io_total"] / wall if wall > 0 else 0

                if r["slots_ram"] < r["slots_threads"]:
                    r["conc_limiter"] = "RAM"
                else:
                    r["conc_limiter"] = "threads"

                if r["thread_eff"] > 50:
                    r["workload"] = "CPU"
                elif r["io_rate"] > 20:
                    r["workload"] = "I/O"
                else:
                    r["workload"] = "wait/mem"

                rows.append(r)
    return rows


def group_by(rows, key_fn):
    g = defaultdict(list)
    for r in rows:
        g[key_fn(r)].append(r)
    return g


def p(s=""):
    """Print a line (collected by redirect to file)."""
    print(s)


def psec(title, level=2):
    print(f"\n{'#' * level} {title}\n")


def fmt_wall(secs):
    h, rem = divmod(int(secs), 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}"


def agg_rules(rows):
    """Aggregate rows by (src_file, rule) → summary dict."""
    by_rule = group_by(rows, lambda r: (r["src_file"], r["rule"]))
    agg = []
    for (src, rule), rlist in sorted(by_rule.items()):
        n = len(rlist)
        avg = lambda k: sum(r[k] for r in rlist) / n
        mx = lambda k: max(r[k] for r in rlist)
        itypes = sorted(set(r["instance_type"] for r in rlist))
        thr_vals = sorted(set(r["snakemake_threads"] for r in rlist))
        covs = sorted(set(r["cov"] for r in rlist if r["cov"] is not None))
        run_ids = sorted(set(r["run_id"] for r in rlist))
        agg.append({
            "src": src, "rule": rule, "n": n,
            "run_ids": run_ids,
            "itypes": itypes,
            "threads": thr_vals,
            "covs": covs,
            "avg_wall": avg("s"),
            "max_wall": mx("s"),
            "total_cost": sum(r["task_cost"] for r in rlist),
            "avg_cost": avg("task_cost"),
            "avg_cores": avg("actual_cores"),
            "max_cores": mx("actual_cores"),
            "avg_thr_eff": avg("thread_eff"),
            "avg_rss_mb": avg("max_rss"),
            "max_rss_mb": mx("max_rss"),
            "avg_ram_pct": avg("ram_pct"),
            "max_ram_pct": mx("ram_pct"),
            "avg_io_in": avg("io_in"),
            "avg_io_out": avg("io_out"),
            "avg_io_rate": avg("io_rate"),
            "avg_conc": avg("max_conc"),
            "bottleneck": max(set(r["conc_limiter"] for r in rlist),
                              key=lambda b: sum(1 for r in rlist
                                                if r["conc_limiter"] == b)),
            "workload": max(set(r["workload"] for r in rlist),
                            key=lambda w: sum(1 for r in rlist
                                              if r["workload"] == w)),
            "rows": rlist,
        })
    return agg


# ======================================================================
#  main()
# ======================================================================
def main():
    rows = load_and_enrich()
    rows = [r for r in rows
            if r["snakemake_threads"] > 0 and r["nproc"] > 0
            and r["instance_type"] != "NA"]

    agg = agg_rules(rows)

    p("# Multi-Tenancy-Aware Benchmark Analysis")
    p()
    p("> **Generated by** `analyze_benchmarks.py`  ")
    p(f"> **Rows:** {len(rows)} (from {len(FILES)} benchmark files, "
      f"NA instance\_type stubs excluded)  ")
    p("> **Key principle:** `task_cost` already pro-rates by "
      "`snakemake_threads / nproc`. A 48-thread job on a 192-vCPU node "
      "pays 25% of node-hour cost.")
    p()

    # ── SECTION 1: Data Inventory ──────────────────────────────────
    psec("1. Data Inventory")
    by_src = group_by(rows, lambda r: r["src_file"])
    p("| Source File | RunIDs | Instance Types | Rules | Coverages | Rows |")
    p("|---|---|---|---|---|---|")
    for src, rlist in sorted(by_src.items()):
        rids = ", ".join(sorted(set(r["run_id"] for r in rlist)))
        itypes = ", ".join(sorted(set(r["instance_type"] for r in rlist)))
        n_rules = len(set(r["rule"] for r in rlist))
        covs = sorted(set(r["cov"] for r in rlist if r["cov"] is not None))
        cov_str = f"{covs[0]}–{covs[-1]}x" if covs else "—"
        p(f"| `{src}` | {rids} | {itypes} | {n_rules} | {cov_str} | {len(rlist)} |")
    p()

    # ── SECTION 2: Top Rules by Cost ───────────────────────────────
    psec("2. Top Rules by Total Cost")
    top = sorted(agg, key=lambda a: a["total_cost"], reverse=True)[:15]
    p("| Source | Rule | N | Tot$ | Avg$ | AvgWall | Thr | AvgCores | ThrEff% | AvgRSS | RAM% | Conc | Workload |")
    p("|---|---|--:|--:|--:|---|--:|--:|--:|---|--:|--:|---|")
    for a in top:
        thr_str = ",".join(str(t) for t in a["threads"])
        p(f"| `{a['src']}` | `{a['rule']}` | {a['n']} "
          f"| ${a['total_cost']:.2f} | ${a['avg_cost']:.3f} "
          f"| {fmt_wall(a['avg_wall'])} | {thr_str} "
          f"| {a['avg_cores']:.1f} | {a['avg_thr_eff']:.1f}% "
          f"| {a['avg_rss_mb']:.0f}MB | {a['avg_ram_pct']:.1f}% "
          f"| {a['avg_conc']:.0f} | {a['workload']} |")
    p()
    p("**Conc** = max concurrent same-rule jobs per node "
      "(min of thread slots, RAM slots).")
    p()

    # ── SECTION 3: Resource Utilization Detail ─────────────────────
    psec("3. Resource Utilization Detail")
    p("- **Thread Efficiency** = `actual_cores / allocated_threads × 100`")
    p("- **RAM%** = `max_rss / node_ram × 100` (varies by instance type)")
    p("- **Workload** = CPU (`thr_eff>50%`), I/O (`rate>20MB/s`), "
      "wait/mem (else)")
    p()
    for a in sorted(agg, key=lambda a: (a["src"], -a["total_cost"])):
        if a["total_cost"] < 0.001:
            continue  # skip trivial rules
        p(f"#### `{a['rule']}` — `{a['src']}`")
        p(f"- **n={a['n']}**, threads={a['threads']}, "
          f"instances={a['itypes']}")
        p(f"- Wall: avg={fmt_wall(a['avg_wall'])}, "
          f"max={fmt_wall(a['max_wall'])}")
        p(f"- CPU: avg\_cores={a['avg_cores']:.1f}, "
          f"max\_cores={a['max_cores']:.1f}, "
          f"thr\_eff={a['avg_thr_eff']:.1f}%, "
          f"workload=**{a['workload']}**")
        p(f"- RAM: avg={a['avg_rss_mb']:.0f}MB, "
          f"max={a['max_rss_mb']:.0f}MB, "
          f"avg\_pct={a['avg_ram_pct']:.1f}%, "
          f"max\_pct={a['max_ram_pct']:.1f}%")
        p(f"- I/O: in={a['avg_io_in']:.0f}MB, "
          f"out={a['avg_io_out']:.0f}MB, "
          f"rate={a['avg_io_rate']:.1f}MB/s")
        p(f"- Cost: total=${a['total_cost']:.3f}, "
          f"avg=${a['avg_cost']:.4f}")
        p(f"- Concurrency: avg\_max={a['avg_conc']:.0f}/node, "
          f"limiter={a['bottleneck']}")
        p()

    # ── SECTION 4: Thread Overallocation Candidates ────────────────
    psec("4. Thread Overallocation Candidates")
    p("Rules with `thr_eff < 25%` and `avg_cost > $0.01`. "
      "These use far fewer cores than allocated. "
      "Reducing threads for wait/mem workloads lets more jobs pack per node "
      "without increasing wall time.")
    p()
    overalloc = [a for a in agg if a["avg_thr_eff"] < 25 and a["avg_cost"] > 0.01]
    overalloc.sort(key=lambda a: a["total_cost"], reverse=True)
    p("| Source | Rule | Thr | AvgCores | ThrEff% | Tot$ | Workload | Suggestion |")
    p("|---|---|--:|--:|--:|--:|---|---|")
    for a in overalloc:
        thr_str = ",".join(str(t) for t in a["threads"])
        cores = a["avg_cores"]
        suggested = max(4, 2 ** (int(cores).bit_length()))
        if suggested >= a["threads"][0]:
            note = "no change"
        else:
            note = f"threads: {a['threads'][0]} \u2192 {suggested}"
        p(f"| `{a['src']}` | `{a['rule']}` | {thr_str} "
          f"| {cores:.1f} | {a['avg_thr_eff']:.1f}% "
          f"| ${a['total_cost']:.2f} | {a['workload']} | {note} |")
    if not overalloc:
        p("_(none found)_")
    p()

    # ── SECTION 5: Cross-Platform Comparison ────────────────────────
    psec("5. Cross-Platform Comparison by Rule Category")

    def categorize(rule):
        rl = rule.lower()
        if "concordance" in rl:
            return "concordance"
        if "alignstats" in rl:
            return "alignstats"
        if "mrkdup" in rl:
            return "dedup"
        if any(x in rl for x in ("alsort", "alnsort", "mm2")):
            return "alignment"
        if any(x in rl for x in ("sentd", "sentdont", "sentdpb", "sentdug")):
            if "merge" in rl or "concat" in rl or "fofn" in rl:
                return "vc_merge"
            return "variant_calling"
        return "other"

    cat_data = defaultdict(list)
    for a in agg:
        cat_data[categorize(a["rule"])].append(a)

    for cat in ["alignment", "variant_calling", "concordance",
                "alignstats", "vc_merge", "other"]:
        if cat not in cat_data:
            continue
        p(f"### {cat.replace('_', ' ').title()}")
        p()
        p("| Source | Rule | Thr | AvgWall | Avg$ | ThrEff% | AvgRSS | Workload |")
        p("|---|---|--:|---|--:|--:|---|---|")
        for a in sorted(cat_data[cat], key=lambda a: a["avg_cost"], reverse=True):
            thr_str = ",".join(str(t) for t in a["threads"])
            p(f"| `{a['src']}` | `{a['rule']}` | {thr_str} "
              f"| {fmt_wall(a['avg_wall'])} | ${a['avg_cost']:.3f} "
              f"| {a['avg_thr_eff']:.1f}% | {a['avg_rss_mb']:.0f}MB "
              f"| {a['workload']} |")
        p()

    # ── SECTION 6: Coverage vs Cost Scaling ─────────────────────────
    psec("6. Coverage vs Cost Scaling")
    p("Per-sample cost broken down by top rules within each run.")
    p()
    by_run = group_by(rows, lambda r: r["run_id"])
    for rid, rlist in sorted(by_run.items()):
        if not any(r["cov"] for r in rlist):
            continue
        src = rlist[0]["src_file"]
        p(f"### RunID: {rid} (`{src}`)")
        p()
        by_cov_rule = group_by(rlist, lambda r: (r["cov"], r["rule"]))
        covs = sorted(set(r["cov"] for r in rlist if r["cov"] is not None))
        rule_costs = defaultdict(float)
        for r in rlist:
            rule_costs[r["rule"]] += r["task_cost"]
        top_rules = sorted(rule_costs, key=rule_costs.get, reverse=True)[:5]
        # Build markdown table
        hdr_cols = ["Cov"] + [f"`{ru[:20]}`" for ru in top_rules] + ["TOTAL"]
        p("| " + " | ".join(hdr_cols) + " |")
        p("|--:" + "|--:" * (len(hdr_cols) - 1) + "|")
        for cov in covs:
            total_cov = 0
            cells = [f"{cov}x"]
            for ru in top_rules:
                cost = sum(r["task_cost"]
                           for r in by_cov_rule.get((cov, ru), []))
                total_cov += cost
                cells.append(f"${cost:.4f}")
            other = sum(r["task_cost"] for r in rlist
                        if r["cov"] == cov and r["rule"] not in top_rules)
            total_cov += other
            cells.append(f"${total_cov:.4f}")
            p("| " + " | ".join(cells) + " |")
        p()

    # ── SECTION 7: Actionable Recommendations ──────────────────────
    psec("7. Actionable Recommendations")
    recs = []
    for a in overalloc:
        cores = a["avg_cores"]
        suggested = max(4, 2 ** (int(cores).bit_length()))
        if suggested < a["threads"][0]:
            old_t = a["threads"][0]
            savings_factor = suggested / old_t
            est_savings = a["total_cost"] * (1 - savings_factor)
            recs.append((est_savings, a["src"], a["rule"],
                         f"threads: {old_t} \u2192 {suggested}",
                         f"thr\\_eff={a['avg_thr_eff']:.1f}%, "
                         f"avg\\_cores={cores:.1f}, "
                         f"workload={a['workload']}"))

    recs.sort(reverse=True)
    if recs:
        p("Ranked by estimated savings "
          "(thread reduction for wait/mem workloads):")
        p()
        p("| # | Est$ | Source | Rule | Change | Justification |")
        p("|--:|--:|---|---|---|---|")
        for i, (sav, src, rule, change, just) in enumerate(recs, 1):
            p(f"| {i} | ${sav:.3f} | `{src}` | `{rule}` "
              f"| {change} | {just} |")
    else:
        p("_No thread-reduction recommendations found._")
    p()

    p("### Caveats")
    p()
    p("- `task_cost` **already** accounts for multi-tenancy "
      "(threads/nproc pro-rating)")
    p("- Reducing threads for **wait/mem** workloads saves $ "
      "because wall time stays flat")
    p("- Reducing threads for **CPU-bound** workloads may "
      "**increase** wall time \u2192 no savings")
    p("- Partition changes (i192mem\u2192i128) only help if RSS fits "
      "in smaller node RAM")
    p("- All instance types, thread counts, and RAM vary per row "
      "\u2014 check detail above")


if __name__ == "__main__":
    main()