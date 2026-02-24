#!/usr/bin/env python3
"""Full audit of all giab_concordance_mqc.tsv files."""
import os, csv, hashlib

BD = "/Users/jmajor/projects/daylily/daylily-omics-analysis/_analysis_data/agbt_benchmark_alignment_concordance_stats"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tmp_audit_output.txt")

SCRIPT_GROUPS = [
    "hio_cli", "hio_fillin", "hio_old",
    "ilmn_all_downsamples_a", "ilmn_hg003_ilmn_sentonly", "ilmn_read_trim",
    "ont_ds", "pacbio_ds", "roche_ds", "roche_ds_fillinone",
    "ultima_ds", "ont_dv19", "ilmn_gatk_b", "dragen_fullold",
]

def md5file(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def analyze(filepath):
    with open(filepath, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        rows = list(reader)
    cols = reader.fieldnames or []
    sc_key = "SNPClass" if "SNPClass" in cols else ("VariantClass" if "VariantClass" in cols else None)
    samples = sorted(set(r.get("Sample", "") for r in rows))
    callers = sorted(set(r.get("SNVCaller", r.get("Caller", "?")) for r in rows))
    aligners = sorted(set(r.get("Aligner", "?") for r in rows))
    footprints = sorted(set(r.get("CmpFootprint", "?") for r in rows))
    classes = sorted(set(r.get(sc_key, "?") for r in rows)) if sc_key else ["?"]
    return {
        "rows": len(rows), "cols": len(cols), "col_names": cols,
        "samples": samples, "callers": callers, "aligners": aligners,
        "footprints": footprints, "classes": classes, "sc_key": sc_key,
    }

lines = []
def p(s=""): lines.append(s)

# Find all giab_concordance_mqc.tsv files
found = {}
for root, dirs, files in os.walk(BD):
    for fn in files:
        if fn == "giab_concordance_mqc.tsv":
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, BD)
            topdir = rel.split("/")[0]
            found[rel] = (topdir, full)

# Classify
in_script = {}
not_in_script = {}
for rel, (topdir, full) in sorted(found.items()):
    if topdir in SCRIPT_GROUPS:
        in_script[rel] = (topdir, full)
    else:
        not_in_script[rel] = (topdir, full)

# All top-level dirs
all_dirs = sorted(d for d in os.listdir(BD) if os.path.isdir(os.path.join(BD, d)) and not d.startswith("__") and not d.startswith("heatmaps"))

p("=" * 70)
p(f"FULL AUDIT: {len(found)} giab_concordance_mqc.tsv files found")
p(f"  In consolidation script: {len(in_script)}")
p(f"  NOT in consolidation script: {len(not_in_script)}")
p(f"  Total directories (excl heatmaps/pycache): {len(all_dirs)}")
p("=" * 70)

p("\n### NOT IN CONSOLIDATION SCRIPT ###\n")
for rel, (topdir, full) in sorted(not_in_script.items()):
    info = analyze(full)
    p(f"[{topdir}] ({rel})")
    p(f"  rows={info['rows']}  samples={len(info['samples'])}  cols={info['cols']}")
    p(f"  callers: {', '.join(info['callers'])}")
    p(f"  aligners: {', '.join(info['aligners'])}")
    p(f"  footprints: {', '.join(info['footprints'])}")
    p(f"  classes: {', '.join(info['classes'])}")
    p(f"  samples: {', '.join(info['samples'][:5])}{'...' if len(info['samples'])>5 else ''}")
    p(f"  md5: {md5file(full)}")
    p()

p("\n### IN CONSOLIDATION SCRIPT ###\n")
for rel, (topdir, full) in sorted(in_script.items()):
    info = analyze(full)
    p(f"[{topdir}] ({rel})")
    p(f"  rows={info['rows']}  samples={len(info['samples'])}  cols={info['cols']}")
    p(f"  callers: {', '.join(info['callers'])}")
    p(f"  aligners: {', '.join(info['aligners'])}")
    p(f"  footprints: {', '.join(info['footprints'])}")
    p(f"  samples: {', '.join(info['samples'][:3])}{'...' if len(info['samples'])>3 else ''}")
    p()

p("\n### DIRS WITH NO giab_concordance_mqc.tsv ###\n")
dirs_with_file = set(topdir for _, (topdir, _) in found.items())
for d in all_dirs:
    if d not in dirs_with_file:
        contents = os.listdir(os.path.join(BD, d))
        p(f"  {d}: {', '.join(contents[:5])}")

p("\n### DUPLICATE CHECK ###\n")
hashes = {}
for rel, (topdir, full) in sorted(found.items()):
    h = md5file(full)
    hashes.setdefault(h, []).append(topdir)
for h, dirs in hashes.items():
    if len(dirs) > 1:
        p(f"  IDENTICAL FILES: {', '.join(dirs)} (md5={h})")

text = "\n".join(lines)
with open(OUT, "w") as f:
    f.write(text)
print(f"Audit written to {OUT} ({len(lines)} lines)")

