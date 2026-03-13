#!/usr/bin/env python3
"""Audit all src_data subdirectories for concordance data."""
import csv
import os
import re
import sys
from collections import defaultdict

SRC = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "_analysis_data/agbt_benchmark_alignment_concordance_stats/src_data",
)
SRC = os.path.normpath(SRC)

# Find all giab_concordance_mqc.tsv files recursively
conc_files = []
for root, dirs, files in os.walk(SRC):
    for f in files:
        if f == "giab_concordance_mqc.tsv":
            conc_files.append(os.path.join(root, f))
conc_files.sort()

print(f"Source directory: {SRC}")
print(f"Found {len(conc_files)} giab_concordance_mqc.tsv files\n")

# Coverage extraction patterns
COV_HIO = re.compile(r"SR(\d+)x-ONT(\d+)x")
COV_SIMPLE = re.compile(r"[_-](\d+)x[_-]")
COV_FRAC = re.compile(r"(\d+)p(\d+)x")

results = []

for cpath in conc_files:
    rel = os.path.relpath(cpath, SRC)
    dir_name = rel.replace("/giab_concordance_mqc.tsv", "")

    aligners = set()
    callers = set()
    samples = set()
    coverages = set()
    row_count = 0
    col_names_raw = set()
    footprints = set()
    variant_classes = set()

    with open(cpath, "r") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        col_names_raw = set(reader.fieldnames) if reader.fieldnames else set()
        for row in reader:
            row_count += 1
            aligners.add(row.get("Aligner", ""))
            callers.add(row.get("SNVCaller", ""))
            sample = row.get("Sample", "")
            samples.add(sample)

            # Extract footprint/ROI
            fp = row.get("ROI", row.get("CmpFootprint", ""))
            if fp:
                footprints.add(fp)

            # Extract variant class
            vc = row.get("VariantClass", row.get("SNPClass", ""))
            if vc:
                variant_classes.add(vc)

            # Extract coverage from sample name
            hio_m = COV_HIO.search(sample)
            frac_m = COV_FRAC.search(sample)
            simple_m = COV_SIMPLE.search(sample)
            if hio_m:
                coverages.add(f"SR{hio_m.group(1)}x-ONT{hio_m.group(2)}x")
            elif frac_m:
                coverages.add(f"{frac_m.group(1)}.{frac_m.group(2)}x")
            elif simple_m:
                coverages.add(f"{simple_m.group(1)}x")

    # Determine column naming convention
    uses_snpclass = "SNPClass" in col_names_raw
    uses_variantclass = "VariantClass" in col_names_raw
    col_convention = "SNPClass/CmpFootprint" if uses_snpclass else "VariantClass/ROI"

    # Determine platform
    platform = "UNKNOWN"
    if any("HIO" in s for s in samples) and any("ONT" in s for s in samples):
        platform = "HYBRID-ILMN+ONT"
    elif any("HUO" in s for s in samples):
        platform = "HYBRID-ULTIMA+ONT"
    elif any(a in ("ont", "sentmm2", "sentmm2ont") for a in aligners):
        if any(c in ("sentdhuo",) for c in callers):
            platform = "HYBRID-ULTIMA+ONT"
        elif any(c in ("sentdhiom", "sentdhiomr", "sentdhio") for c in callers):
            platform = "HYBRID-ILMN+ONT"
        elif any(c in ("sentdont", "deep19") for c in callers):
            platform = "ONT"
        else:
            platform = "ONT"
    elif any(a in ("ug",) for a in aligners):
        platform = "ULTIMA"
    elif any(a in ("roche",) for a in aligners):
        platform = "ROCHE"
    elif any(a in ("sentmm2pb",) for a in aligners):
        platform = "PACBIO"
    elif any(a in ("bwa2a", "sent", "bwa", "bwa2", "dragen") for a in aligners):
        platform = "ILMN"
    elif any(a in ("sentpan",) for a in aligners):
        platform = "ILMN-PANGENOME"

    results.append({
        "dir": dir_name,
        "rows": row_count,
        "aligners": sorted(aligners),
        "callers": sorted(callers),
        "samples_count": len(samples),
        "samples": sorted(samples),
        "coverages": sorted(coverages, key=lambda x: (len(x), x)),
        "platform": platform,
        "footprints": sorted(footprints),
        "variant_classes": sorted(variant_classes),
        "col_convention": col_convention,
    })

print("=" * 120)
print(f"{'DIR':<35} {'ROWS':>6} {'PLATFORM':<22} {'ALIGNERS':<25} {'CALLERS':<30} {'#SAMP':>5} {'COV_CONVENTION':<20}")
print("=" * 120)
for r in results:
    print(f"{r['dir']:<35} {r['rows']:>6} {r['platform']:<22} {','.join(r['aligners']):<25} {','.join(r['callers']):<30} {r['samples_count']:>5} {r['col_convention']:<20}")
print("=" * 120)
print()

# Detailed per-directory output
for r in results:
    print(f"\n{'='*80}")
    print(f"  DIRECTORY: {r['dir']}")
    print(f"{'='*80}")
    print(f"  Rows:             {r['rows']}")
    print(f"  Platform:         {r['platform']}")
    print(f"  Aligners:         {', '.join(r['aligners'])}")
    print(f"  Callers:          {', '.join(r['callers'])}")
    print(f"  Samples ({r['samples_count']:>3}):    {', '.join(r['samples'][:10])}")
    if r['samples_count'] > 10:
        print(f"                    ... and {r['samples_count'] - 10} more")
    print(f"  Coverages:        {', '.join(r['coverages'][:15])}")
    if len(r['coverages']) > 15:
        print(f"                    ... and {len(r['coverages']) - 15} more")
    print(f"  Footprints:       {', '.join(r['footprints'])}")
    print(f"  Variant classes:  {', '.join(r['variant_classes'])}")
    print(f"  Column naming:    {r['col_convention']}")

