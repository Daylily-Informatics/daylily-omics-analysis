#!/usr/bin/env python3
"""Filter ont_filler data files: remove specified samples, create units file."""
import csv
import os
import re

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ont_patch")

# Samples to REMOVE (match on RUNID-SAMPLEID-EXPERIMENTID prefix)
REMOVE_PREFIXES = [
    "On1b-HG003-50x",
    "On1-HG003-50x",
    "On1b-HG003-40x",
    "On1-HG003-40x",
    "On1b-HG003-30x",
    "On1-HG003-30x",
    "On1-HG003-5x",
    "On1-HG003-1x",
]


def should_remove(value):
    """Return True if value starts with any of the removal prefixes."""
    for prefix in REMOVE_PREFIXES:
        if value.startswith(prefix + "-") or value == prefix:
            return True
    return False


def filter_tsv(filepath):
    """Filter a TSV file in-place, removing rows matching removal prefixes."""
    with open(filepath) as f:
        lines = f.readlines()

    header = lines[0]
    kept = [header]
    removed = 0
    for line in lines[1:]:
        first_col = line.split("\t")[0]
        if should_remove(first_col):
            removed += 1
        else:
            kept.append(line)

    with open(filepath, "w") as f:
        f.writelines(kept)

    print(f"  {os.path.basename(filepath)}: {removed} rows removed, {len(kept)-1} rows kept")


# --- Filter all TSV data files ---
print("=== Filtering ont_filler data files ===")
for fname in sorted(os.listdir(BASE)):
    fpath = os.path.join(BASE, fname)
    if fname.endswith(".tsv"):
        filter_tsv(fpath)

# --- Create units file ---
# Remaining samples after removal:
# On1: 3x, 7x, 10x, 15x, 20x
# On1b: 15xact, 20x
UNITS_HEADER = (
    "RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\t"
    "SEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\t"
    "PACBIO_R1_PATH\tPACBIO_R2_PATH\tONT_R1_PATH\tONT_R2_PATH\t"
    "UG_R1_PATH\tUG_R2_PATH\tSUBSAMPLE_PCT\tILMN_TRIM_READ_LENGTH\t"
    "SAMPLEUSE\tBWA_KMER\tDEEP_MODEL\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\t"
    "ULTIMA_CRAM_SNV_CALLER\tONT_CRAM\tONT_CRAM_ALIGNER\t"
    "ONT_CRAM_SNV_CALLER\tPB_BAM\tPB_BAM_ALIGNER\tPB_BAM_SNV_CALLER\t"
    "ROCHE_BAM\tROCHE_BAM_ALIGNER\tROCHE_BAM_SNV_CALLER\t"
    "ROCHE_DOWNSAMPLE_RATIO"
)

CRAM_BASE = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont"

# (RUNID, EXPERIMENTID, LANEID, cram_filename)
REMAINING = [
    ("On1", "3x",      "2", "HG003_3x.cleaned.cram"),
    ("On1", "7x",      "4", "HG003_7x.cleaned.cram"),
    ("On1", "10x",     "5", "HG003_10x.cleaned.cram"),
    ("On1", "15x",     "6", "HG003_15x.cleaned.cram"),
    ("On1", "20x",     "7", "HG003_20x.cleaned.cram"),
    ("On1b", "15xact", "6", "HG003_15xactual.cleaned.cram"),
    ("On1b", "20x",    "7", "HG003_20x.cleaned.cram"),
]

units_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "units.tsv")
with open(units_path, "w") as f:
    f.write(UNITS_HEADER + "\n")
    for runid, expid, laneid, cram in REMAINING:
        # 34 columns total, most are empty for ONT-only samples
        cols = [
            runid,          # RUNID
            "HG003",        # SAMPLEID
            expid,          # EXPERIMENTID
            laneid,         # LANEID
            "D0",           # BARCODEID
            "PF",           # LIBPREP
            "ONT",          # SEQ_VENDOR
            "PROMETHION",   # SEQ_PLATFORM
            "", "",         # ILMN_R1_PATH, ILMN_R2_PATH
            "", "",         # PACBIO_R1_PATH, PACBIO_R2_PATH
            "", "",         # ONT_R1_PATH, ONT_R2_PATH
            "", "",         # UG_R1_PATH, UG_R2_PATH
            "",             # SUBSAMPLE_PCT
            "",             # ILMN_TRIM_READ_LENGTH
            "posControl",   # SAMPLEUSE
            "19",           # BWA_KMER
            "ONT_R104",     # DEEP_MODEL
            "", "", "",     # ULTIMA_CRAM, ALIGNER, SNV_CALLER
            f"{CRAM_BASE}/{cram}",  # ONT_CRAM
            "ont",          # ONT_CRAM_ALIGNER
            "sentdont",     # ONT_CRAM_SNV_CALLER
            "", "", "",     # PB_BAM, ALIGNER, SNV_CALLER
            "", "", "",     # ROCHE_BAM, ALIGNER, SNV_CALLER
            "",             # ROCHE_DOWNSAMPLE_RATIO
        ]
        f.write("\t".join(cols) + "\n")

print(f"\n=== Created units file: {units_path} ===")
print(f"  {len(REMAINING)} samples")

# --- Verify remaining samples ---
print("\n=== Remaining samples in alignstats ===")
with open(os.path.join(BASE, "alignstats_combo_mqc.tsv")) as f:
    reader = csv.DictReader(f, delimiter="\t")
    for r in reader:
        s = r["sample"].rsplit(".", 1)[0]
        print(f"  {s}  (mean={r['WgsCoverageMean']}, median={r['WgsCoverageMedian']})")

