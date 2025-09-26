import os
import yaml
import pandas as pd
import numpy as np
from jinja2 import Template

som_pairs = snakemake.input.som_pairs
som_groups = snakemake.input.som_groups
picard_metrics = snakemake.input.picard_metrics
picard_matrix = snakemake.input.picard_matrix
conpair_files = snakemake.input.get("conpair", [])
out_tsv = snakemake.output.tsv
out_html = snakemake.output.html
cfg_path = snakemake.params.cfg

with open(cfg_path, encoding="utf-8") as handle:
    CFG = yaml.safe_load(handle)


sp = pd.read_csv(som_pairs, sep="\t")
sp_cols = {column.lower(): column for column in sp.columns}


def sp_col(name):
    return sp_cols.get(name, name)


def pair_key(sample_a, sample_b):
    return tuple(sorted([sample_a, sample_b]))


sp["pair_key"] = [
    pair_key(a, b)
    for a, b in zip(sp[sp_col("sample_a")], sp[sp_col("sample_b")])
]
sp_pairs = {key: row for key, row in sp.set_index("pair_key").iterrows()}


pm = pd.read_csv(picard_metrics, sep="\t", comment="#")

path2sample = {}
for sample, entry in CFG["samples"].items():
    path = entry.get("bam") or entry.get("vcf")
    if path:
        path2sample[os.path.abspath(path)] = sample


def file_to_sample(path):
    absolute = os.path.abspath(path)
    if absolute in path2sample:
        return path2sample[absolute]
    basename = os.path.basename(absolute)
    for candidate, sample in path2sample.items():
        if os.path.basename(candidate) == basename:
            return sample
    return basename


pm["left_samp"] = pm["LEFT_FILE"].map(file_to_sample)
pm["right_samp"] = pm["RIGHT_FILE"].map(file_to_sample)
pm["pair_key"] = [
    pair_key(a, b) for a, b in zip(pm["left_samp"], pm["right_samp"])
]
pm_best = pm.loc[pm.groupby("pair_key")["LOD_SCORE"].apply(lambda series: series.abs().idxmax())]
picard_pairs = {key: row for key, row in pm_best.set_index("pair_key").iterrows()}


conpair_frames = []
for file_path in conpair_files:
    if not os.path.exists(file_path):
        continue
    try:
        frame = pd.read_csv(file_path, sep="\t")
    except Exception:
        frame = pd.read_csv(file_path)
    frame.columns = [column.lower() for column in frame.columns]
    pair = os.path.basename(os.path.dirname(file_path)).split("__")
    if len(pair) == 2:
        frame["sample_a"], frame["sample_b"] = pair
    conpair_frames.append(frame)

if conpair_frames:
    con_df = pd.concat(conpair_frames, ignore_index=True)
else:
    con_df = pd.DataFrame()


THRESH = {
    "identical_relatedness": 0.95,
    "tn_relatedness": 0.70,
    "first_degree_relatedness": 0.45,
    "ibs0_parent_child": 0,
    "picard_mismatch_lod": -5.0,
    "picard_match_lod": 5.0,
}


def get_somalier(sample_a, sample_b, field):
    row = sp_pairs.get(pair_key(sample_a, sample_b))
    if row is None:
        return None
    return row.get(field, row.get(field.upper()))


def get_picard(sample_a, sample_b):
    row = picard_pairs.get(pair_key(sample_a, sample_b))
    if row is None:
        return None
    return {
        "result": row.get("RESULT", ""),
        "lod": float(row.get("LOD_SCORE", np.nan)),
    }


rows = []
for expectation in CFG.get("expected", []):
    relationship = expectation["relationship"]
    sample_a, sample_b = expectation["samples"]
    note = expectation.get("note", "")

    som_rel = get_somalier(sample_a, sample_b, "relatedness")
    ibs0 = get_somalier(sample_a, sample_b, "ibs0")
    picard_info = get_picard(sample_a, sample_b)

    status = "PASS"
    reasons = []

    if relationship in ("identical", "duplicate"):
        if som_rel is not None and som_rel < THRESH["identical_relatedness"]:
            status = "FAIL"
            reasons.append(
                f"Somalier.relatedness={som_rel:.3f} < {THRESH['identical_relatedness']}"
            )
        if picard_info is not None and picard_info["lod"] < THRESH["picard_match_lod"]:
            status = "FAIL"
            reasons.append(
                f"Picard.LOD={picard_info['lod']:.1f} < {THRESH['picard_match_lod']}"
            )
    elif relationship == "tumor_normal":
        if som_rel is not None and som_rel < THRESH["tn_relatedness"]:
            status = "FAIL"
            reasons.append(
                f"Somalier.relatedness={som_rel:.3f} < {THRESH['tn_relatedness']}"
            )
        if picard_info is not None and picard_info["lod"] <= THRESH["picard_mismatch_lod"]:
            status = "FAIL"
            reasons.append(
                f"Picard.LOD strongly negative ({picard_info['lod']:.1f})"
            )
    elif relationship in ("parent_child", "parent-offspring"):
        if som_rel is not None and som_rel < THRESH["first_degree_relatedness"]:
            status = "FAIL"
            reasons.append(
                f"Somalier.relatedness={som_rel:.3f} < {THRESH['first_degree_relatedness']}"
            )
        if ibs0 is not None and ibs0 > 2:
            status = "FAIL"
            reasons.append(f"Somalier.IBS0={ibs0} > 2 (expected ~0)")
    elif relationship == "siblings":
        if som_rel is not None and som_rel < THRESH["first_degree_relatedness"]:
            status = "FAIL"
            reasons.append(
                f"Somalier.relatedness={som_rel:.3f} < {THRESH['first_degree_relatedness']}"
            )
        if ibs0 is not None and ibs0 <= 0:
            status = "FAIL"
            reasons.append(
                f"Somalier.IBS0={ibs0} <= 0 (siblings typically >0)"
            )
    elif relationship == "unrelated":
        if som_rel is not None and som_rel >= 0.2:
            status = "FAIL"
            reasons.append(
                f"Somalier.relatedness={som_rel:.3f} unexpectedly high for unrelated"
            )
        if picard_info is not None and picard_info["lod"] >= THRESH["picard_match_lod"]:
            status = "FAIL"
            reasons.append(
                f"Picard.LOD={picard_info['lod']:.1f} unexpectedly high for unrelated"
            )
    else:
        reasons.append(f"Unknown relationship: {relationship}")

    rows.append(
        {
            "sample_a": sample_a,
            "sample_b": sample_b,
            "relationship": relationship,
            "note": note,
            "somalier_relatedness": som_rel,
            "somalier_ibs0": ibs0,
            "picard_result": None if picard_info is None else picard_info["result"],
            "picard_lod": None if picard_info is None else picard_info["lod"],
            "status": status,
            "reason": "; ".join(reasons) if reasons else "",
        }
    )

summary = pd.DataFrame(rows).sort_values(
    ["status", "relationship", "sample_a", "sample_b"]
)
os.makedirs(os.path.dirname(out_tsv), exist_ok=True)
summary.to_csv(out_tsv, sep="\t", index=False)


template = Template(
    """
<!doctype html><html><head>
<meta charset="utf-8"><title>Relatedness QC</title>
<style>body{font-family:system-ui,Arial} table{border-collapse:collapse} td,th{border:1px solid #ccc;padding:6px 8px} .FAIL{background:#ffe3e3} .PASS{background:#e6ffed}</style>
</head><body>
<h1>Relatedness QC</h1>
<p><b>Samples:</b> {{ sample_count }} | <b>Somalier pairs:</b> {{ somalier_pairs }} | <b>Picard pairs:</b> {{ picard_pairs }}</p>
<h2>Expectations</h2>
<table>
  <thead><tr>
    <th>Status</th><th>Relationship</th><th>Sample A</th><th>Sample B</th>
    <th>Somalier.relatedness</th><th>Somalier.IBS0</th><th>Picard.LOD</th><th>Notes / Reasons</th>
  </tr></thead>
  <tbody>
  {% for row in rows %}
  <tr class="{{ row.status }}">
    <td>{{ row.status }}</td>
    <td>{{ row.relationship }}</td>
    <td>{{ row.sample_a }}</td>
    <td>{{ row.sample_b }}</td>
    <td>{{ "%.3f"|format(row.somalier_relatedness) if row.somalier_relatedness is not none else "" }}</td>
    <td>{{ row.somalier_ibs0 if row.somalier_ibs0 is not none else "" }}</td>
    <td>{{ "%.1f"|format(row.picard_lod) if row.picard_lod is not none else "" }}</td>
    <td>{{ row.reason or row.note }}</td>
  </tr>
  {% endfor %}
  </tbody>
</table>

<h2>Files</h2>
<ul>
  <li>Somalier: <code>results/somalier/cohort_pairs.tsv</code>, <code>cohort_groups.tsv</code>, <code>cohort.html</code></li>
  <li>Picard: <code>results/picard/crosscheck/metrics.txt</code>, <code>matrix.txt</code></li>
  {% if has_conpair %}<li>Conpair per tumor/normal pair: <code>results/conpair/&lt;T&gt;__&lt;N&gt;/</code></li>{% endif %}
  {% if peddy_enabled %}<li>Peddy: <code>results/peddy/peddy.html</code></li>{% endif %}
</ul>

<p style="margin-top:24px;font-size:90%"><b>Thresholds (heuristic defaults):</b>
identical ≥ {{ thresholds.identical_relatedness }}, tumor-normal ≥ {{ thresholds.tn_relatedness }},
first-degree ≥ {{ thresholds.first_degree_relatedness }},
Picard match LOD ≥ {{ thresholds.picard_match_lod }}, strong mismatch LOD ≤ {{ thresholds.picard_mismatch_lod }}.
</p>
</body></html>
"""
)

html = template.render(
    rows=rows,
    sample_count=len(CFG["samples"]),
    somalier_pairs=len(sp),
    picard_pairs=len(pm),
    has_conpair=bool(conpair_files),
    peddy_enabled=CFG.get("peddy", {}).get("enabled", False),
    thresholds=THRESH,
)

os.makedirs(os.path.dirname(out_html), exist_ok=True)
with open(out_html, "w", encoding="utf-8") as handle:
    handle.write(html)
