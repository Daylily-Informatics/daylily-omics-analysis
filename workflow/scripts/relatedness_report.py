import sys, os, yaml, pandas as pd, numpy as np
from jinja2 import Template

som_pairs = snakemake.input.som_pairs
som_groups = snakemake.input.som_groups
picard_metrics = snakemake.input.picard_metrics
picard_matrix = snakemake.input.picard_matrix
conpair_files = snakemake.input.get("conpair", [])
out_tsv = snakemake.output.tsv
out_html = snakemake.output.html
cfg_path = snakemake.params.cfg

with open(cfg_path) as fh:
    CFG = yaml.safe_load(fh)

# ---------------- Somalier ----------------
sp = pd.read_csv(som_pairs, sep="\t")
# Ensure consistent column presence
# expected columns include: sample_a, sample_b, relatedness, ibs0, ibs2, hom_concordance, het_concordance, etc.
sp_cols = {c.lower(): c for c in sp.columns}
def col(name): return sp_cols.get(name, name)

# Fast lookup for any pair (unordered)
def key(a,b): return tuple(sorted([a,b]))
sp["pair_key"] = [key(a,b) for a,b in zip(sp[col("sample_a")], sp[col("sample_b")])]
sp_pairs = {k: row for k, row in sp.set_index("pair_key").iterrows()}

# ---------------- Picard Crosscheck ----------------
# metrics.txt has columns like: LEFT_FILE, RIGHT_FILE, RESULT, LOD_SCORE, etc.
pm = pd.read_csv(picard_metrics, sep="\t", comment="#")
# map file path -> sample name from config
path2sample = {}
for s,ent in CFG["samples"].items():
    p = ent.get("bam") or ent.get("vcf")
    if p: path2sample[os.path.abspath(p)] = s

def file2sample(p):
    a = os.path.abspath(p)
    # Picard sometimes normalizes paths; try basename fallback
    if a in path2sample: return path2sample[a]
    base = os.path.basename(a)
    for k,v in path2sample.items():
        if os.path.basename(k)==base: return v
    return base

pm["left_samp"]  = pm["LEFT_FILE"].map(file2sample)
pm["right_samp"] = pm["RIGHT_FILE"].map(file2sample)
pm["pair_key"] = [key(a,b) for a,b in zip(pm["left_samp"], pm["right_samp"]) ]

# Collapse to best (max absolute LOD) per pair
pm_best = pm.loc[pm.groupby("pair_key")["LOD_SCORE"].apply(lambda s: s.abs().idxmax())]

picard_pairs = {k: row for k,row in pm_best.set_index("pair_key").iterrows()}

# ---------------- Conpair (tumor/normal) ----------------
con_df = []
for f in conpair_files:
    if not os.path.exists(f): continue
    try:
        df = pd.read_csv(f, sep="\t")
    except Exception:
        # Some versions write CSV-like; be lenient
        df = pd.read_csv(f)
    df.columns = [c.lower() for c in df.columns]
    # Try to capture pair names from path
    pair = os.path.basename(os.path.dirname(f)).split("__")
    df["sample_a"] = pair[0]
    df["sample_b"] = pair[1]
    con_df.append(df)
con_df = pd.concat(con_df, ignore_index=True) if con_df else pd.DataFrame()

# Heuristic thresholds
THRESH = dict(
    identical_relatedness=0.95,      # Somalier ~1.0 for same-individual/duplicate
    tn_relatedness=0.70,             # Tumor-normal often 0.8–1.0; allow LOH/purity wiggle
    first_degree_relatedness=0.45,   # Parent-child or full-sibs ~0.45–0.55 in Somalier
    ibs0_parent_child=0,             # IBS0 = 0 for PO in ideal; allow <= 2 by noise
    picard_mismatch_lod=-5.0,        # strong negative indicates mismatch
    picard_match_lod=5.0             # strong positive indicates match
)

def get_somalier(a,b, field):
    r = sp_pairs.get(key(a,b))
    return None if r is None else r.get(field, r.get(field.upper()))

def get_picard(a,b):
    r = picard_pairs.get(key(a,b))
    if r is None: return None
    return dict(result=r.get("RESULT",""), lod=float(r.get("LOD_SCORE", np.nan)))

# Evaluate expectations
rows = []
for exp in CFG.get("expected", []):
    rel = exp["relationship"]
    a, b = exp["samples"]
    note = exp.get("note","")

    som_rel = get_somalier(a,b, "relatedness")
    ibs0 = get_somalier(a,b, "ibs0")
    pic = get_picard(a,b)

    status = "PASS"
    fail_reasons = []

    if rel in ("identical","duplicate"):
        if som_rel is not None and som_rel < THRESH["identical_relatedness"]:
            status = "FAIL"; fail_reasons.append(f"Somalier.relatedness={som_rel:.3f} < {THRESH['identical_relatedness']}")
        if pic is not None and pic["lod"] < THRESH["picard_match_lod"]:
            status = "FAIL"; fail_reasons.append(f"Picard.LOD={pic['lod']:.1f} < {THRESH['picard_match_lod']}")
    elif rel == "tumor_normal":
        if som_rel is not None and som_rel < THRESH["tn_relatedness"]:
            status = "FAIL"; fail_reasons.append(f"Somalier.relatedness={som_rel:.3f} < {THRESH['tn_relatedness']}")
        if pic is not None and pic["lod"] < 0 and pic["lod"] <= THRESH["picard_mismatch_lod"]:
            status = "FAIL"; fail_reasons.append(f"Picard.LOD strongly negative ({pic['lod']:.1f})")
    elif rel in ("parent_child","parent-offspring"):
        # Expect first-degree + IBS0≈0
        if som_rel is not None and som_rel < THRESH["first_degree_relatedness"]:
            status = "FAIL"; fail_reasons.append(f"Somalier.relatedness={som_rel:.3f} < {THRESH['first_degree_relatedness']}")
        if ibs0 is not None and ibs0 > 2:
            status = "FAIL"; fail_reasons.append(f"Somalier.IBS0={ibs0} > 2 (expected ~0)")
    elif rel == "siblings":
        # Expect first-degree but IBS0>0 typically
        if som_rel is not None and som_rel < THRESH["first_degree_relatedness"]:
            status = "FAIL"; fail_reasons.append(f"Somalier.relatedness={som_rel:.3f} < {THRESH['first_degree_relatedness']}")
        if ibs0 is not None and ibs0 <= 0:
            status = "FAIL"; fail_reasons.append(f"Somalier.IBS0={ibs0} <= 0 (sibs typically >0)")
    elif rel == "unrelated":
        if som_rel is not None and som_rel >= 0.2:
            status = "FAIL"; fail_reasons.append(f"Somalier.relatedness={som_rel:.3f} unexpectedly high for unrelated")
        if pic is not None and pic["lod"] >= THRESH["picard_match_lod"]:
            status = "FAIL"; fail_reasons.append(f"Picard.LOD={pic['lod']:.1f} unexpectedly high for unrelated")
    else:
        fail_reasons.append(f"Unknown relationship: {rel}")

    rows.append(dict(
        sample_a=a, sample_b=b, relationship=rel, note=note,
        somalier_relatedness=som_rel,
        somalier_ibs0=ibs0,
        picard_result=None if pic is None else pic["result"],
        picard_lod=None if pic is None else pic["lod"],
        status=status, reason="; ".join(fail_reasons) if fail_reasons else ""
    ))

summary = pd.DataFrame(rows).sort_values(["status","relationship","sample_a","sample_b"])
os.makedirs(os.path.dirname(out_tsv), exist_ok=True)
summary.to_csv(out_tsv, sep="\t", index=False)

# Minimal HTML (table + quick hints)
tpl = Template("""
<!doctype html><html><head>
<meta charset="utf-8"><title>Relatedness QC</title>
<style>body{font-family:system-ui,Arial} table{border-collapse:collapse} td,th{border:1px solid #ccc;padding:6px 8px} .FAIL{background:#ffe3e3} .PASS{background:#e6ffed}</style>
</head><body>
<h1>Relatedness QC</h1>
<p><b>Samples:</b> {{ ns }} | <b>Somalier pairs:</b> {{ n_pairs }} | <b>Picard pairs:</b> {{ n_picard }}</p>
<h2>Expectations</h2>
<table>
  <thead><tr>
    <th>Status</th><th>Relationship</th><th>Sample A</th><th>Sample B</th>
    <th>Somalier.relatedness</th><th>Somalier.IBS0</th><th>Picard.LOD</th><th>Notes / Reasons</th>
  </tr></thead>
  <tbody>
  {% for r in rows %}
  <tr class="{{ r.status }}">
    <td>{{ r.status }}</td>
    <td>{{ r.relationship }}</td>
    <td>{{ r.sample_a }}</td>
    <td>{{ r.sample_b }}</td>
    <td>{{ "%.3f"|format(r.somalier_relatedness) if r.somalier_relatedness is not none else "" }}</td>
    <td>{{ r.somalier_ibs0 if r.somalier_ibs0 is not none else "" }}</td>
    <td>{{ "%.1f"|format(r.picard_lod) if r.picard_lod is not none else "" }}</td>
    <td>{{ r.reason or r.note }}</td>
  </tr>
  {% endfor %}
  </tbody>
</table>

<h2>Files</h2>
<ul>
  <li>Somalier: <code>results/somalier/cohort_pairs.tsv</code>, <code>cohort_groups.tsv</code>, <code>cohort.html</code></li>
  <li>Picard: <code>results/picard/crosscheck/metrics.txt</code>, <code>matrix.txt</code></li>
  {% if has_conpair %}<li>Conpair per TN pair: <code>results/conpair/&lt;T&gt;__&lt;N&gt;/</code></li>{% endif %}
  {% if peddy_enabled %}<li>Peddy: <code>results/peddy/peddy.html</code></li>{% endif %}
</ul>

<p style="margin-top:24px;font-size:90%"><b>Thresholds (heuristic defaults):</b>
identical ≥ {{th.identical_relatedness}}, tumor-normal ≥ {{th.tn_relatedness}},
first-degree ≥ {{th.first_degree_relatedness}},
Picard match LOD ≥ {{th.picard_match_lod}}, strong mismatch LOD ≤ {{th.picard_mismatch_lod}}.
</p>
</body></html>
""")
html = tpl.render(
    rows=rows,
    ns=len(CFG["samples"]),
    n_pairs=len(sp),
    n_picard=len(pm),
    has_conpair=len(conpair_files)>0,
    peddy_enabled=CFG.get("peddy",{}).get("enabled", False),
    th=THRESH
)
with open(out_html,"w") as f:
    f.write(html)
