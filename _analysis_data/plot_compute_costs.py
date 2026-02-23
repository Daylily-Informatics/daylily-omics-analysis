#!/usr/bin/env python3
"""Generate plots for AWS compute cost analysis report."""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import os

OUT = os.path.dirname(os.path.abspath(__file__))

# --- Data ---
instances = [
    "r6i.2xlarge", "r7i.2xlarge", "c6i.32xlarge", "m6i.32xlarge", "r6i.32xlarge",
    "c7i.48xlarge", "c7i.metal-48xl", "m7i.48xlarge", "m7i.metal-48xl",
    "r7i.48xlarge", "r7i.metal-48xl",
]
partitions = ["i8","i8","i128","i128","i128","i192","i192","i192mem","i192mem","i192bigmem","i192bigmem"]
vcpus = [8, 8, 128, 128, 128, 192, 192, 192, 192, 192, 192]
od_hr = [0.5040, 0.5292, 5.4400, 6.1440, 8.0640, 8.5680, 8.5680, 9.6768, 9.6768, 12.7008, 12.7008]
spot_hr = [0.2182, 0.2299, 1.9176, 1.9134, 3.0735, 3.9752, 2.5336, 4.7666, 2.9257, 4.1475, 2.8058]
spot_vcpu = [s/v for s, v in zip(spot_hr, vcpus)]
od_vcpu = [o/v for o, v in zip(od_hr, vcpus)]
spot_discount = [(1 - s/o)*100 for s, o in zip(spot_hr, od_hr)]

plt.rcParams.update({"font.family": "sans-serif", "font.size": 11, "figure.dpi": 150})
colors = {"i8": "#ef4444", "i128": "#f59e0b", "i192": "#22c55e", "i192mem": "#3b82f6", "i192bigmem": "#8b5cf6"}
part_colors = [colors[p] for p in partitions]

# ---- Plot 1: On-Demand vs Spot $/hr ----
fig, ax = plt.subplots(figsize=(12, 5))
x = np.arange(len(instances))
w = 0.35
bars_od = ax.bar(x - w/2, od_hr, w, label="On-Demand", color="#6366f1", alpha=0.85, edgecolor="white", linewidth=0.5)
bars_sp = ax.bar(x + w/2, spot_hr, w, label="Spot (24hr avg)", color="#22c55e", alpha=0.85, edgecolor="white", linewidth=0.5)
ax.set_ylabel("$/hr")
ax.set_title("On-Demand vs Spot Pricing — us-west-2", fontweight="bold")
ax.set_xticks(x)
ax.set_xticklabels(instances, rotation=40, ha="right", fontsize=9)
ax.legend()
ax.grid(axis="y", alpha=0.3)
for i, (o, s) in enumerate(zip(od_hr, spot_hr)):
    ax.annotate(f"{(1-s/o)*100:.0f}%", xy=(i + w/2, s), ha="center", va="bottom", fontsize=7, color="#166534", fontweight="bold")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "cost_ondemand_vs_spot.png"), bbox_inches="tight")
plt.close(fig)
print("Saved cost_ondemand_vs_spot.png")

# ---- Plot 2: Per-vCPU Cost Ranking (spot) ----
order = sorted(range(len(instances)), key=lambda i: spot_vcpu[i])
fig, ax = plt.subplots(figsize=(10, 5))
bars = ax.barh(
    [instances[i] for i in order],
    [spot_vcpu[i] for i in order],
    color=[part_colors[i] for i in order],
    edgecolor="white", linewidth=0.5, alpha=0.9,
)
for bar, idx in zip(bars, order):
    ax.text(bar.get_width() + 0.0003, bar.get_y() + bar.get_height()/2,
            f"${spot_vcpu[idx]:.4f}  [{partitions[idx]}]", va="center", fontsize=9)
ax.set_xlabel("$/vCPU/hr (spot)")
ax.set_title("Per-vCPU Spot Cost Ranking — Cheapest to Most Expensive", fontweight="bold")
ax.set_xlim(0, max(spot_vcpu)*1.35)
ax.grid(axis="x", alpha=0.3)
from matplotlib.patches import Patch
legend_elems = [Patch(facecolor=colors[p], label=p) for p in colors]
ax.legend(handles=legend_elems, loc="lower right", fontsize=9, title="Partition")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "cost_per_vcpu_ranking.png"), bbox_inches="tight")
plt.close(fig)
print("Saved cost_per_vcpu_ranking.png")

# ---- Plot 3: .metal vs .48xlarge spot comparison ----
pairs = [
    ("c7i.48xlarge", "c7i.metal-48xl", "i192"),
    ("m7i.48xlarge", "m7i.metal-48xl", "i192mem"),
    ("r7i.48xlarge", "r7i.metal-48xl", "i192bigmem"),
]
fig, ax = plt.subplots(figsize=(8, 4.5))
x = np.arange(len(pairs))
w = 0.3
for i, (xlarge, metal, part) in enumerate(pairs):
    ix_xl = instances.index(xlarge)
    ix_mt = instances.index(metal)
    ax.bar(i - w/2, spot_hr[ix_xl], w, color="#ef4444", alpha=0.85, edgecolor="white",
           label=".48xlarge" if i == 0 else "")
    ax.bar(i + w/2, spot_hr[ix_mt], w, color="#22c55e", alpha=0.85, edgecolor="white",
           label=".metal-48xl" if i == 0 else "")
    saving = (1 - spot_hr[ix_mt]/spot_hr[ix_xl]) * 100
    ax.annotate(f"−{saving:.0f}%", xy=(i + w/2, spot_hr[ix_mt]), ha="center", va="bottom",
                fontsize=10, color="#166534", fontweight="bold")
ax.set_xticks(x)
ax.set_xticklabels([p[2] for p in pairs], fontsize=11)
ax.set_ylabel("$/hr (spot avg)")
ax.set_title(".metal-48xl vs .48xlarge Spot Pricing", fontweight="bold")
ax.legend()
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "cost_metal_vs_xlarge.png"), bbox_inches="tight")
plt.close(fig)
print("Saved cost_metal_vs_xlarge.png")

# ---- Plot 4: Spot Discount % by Instance ----
fig, ax = plt.subplots(figsize=(10, 5))
ax.barh(instances, spot_discount, color=part_colors, edgecolor="white", linewidth=0.5, alpha=0.9)
for i, d in enumerate(spot_discount):
    ax.text(d + 0.5, i, f"{d:.0f}%", va="center", fontsize=9)
ax.set_xlabel("Spot Discount vs On-Demand (%)")
ax.set_title("Spot Discount by Instance Type", fontweight="bold")
ax.set_xlim(0, 100)
ax.grid(axis="x", alpha=0.3)
ax.legend(handles=legend_elems, loc="lower right", fontsize=9, title="Partition")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "cost_spot_discount.png"), bbox_inches="tight")
plt.close(fig)
print("Saved cost_spot_discount.png")

print("\nAll plots saved to:", OUT)

