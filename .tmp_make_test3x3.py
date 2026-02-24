#!/usr/bin/env python3
"""Generate 3x3 test units.tsv for stage1 fix validation."""

# Read exact header from core_units.tsv
CORE = ".test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/core_units.tsv"
with open(CORE) as f:
    HEADER = f.readline().rstrip("\n")
    # Read one data row to use as template
    template_row = f.readline().rstrip("\n").split("\t")

NCOLS = len(HEADER.split("\t"))
print(f"Header has {NCOLS} columns")

ILMN_BASE = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled"
ONT_BASE = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont"

SR_LEVELS = [
    ("SR3x", "HG003_3x"),
    ("SR7x", "HG003_7x"),
    ("SR15x", "HG003_15x"),
]

ONT_LEVELS = [
    ("ONT3x", "HG003_7x.cleaned.cram"),
    ("ONT7x", "HG003_15x.cleaned.cram"),
    ("ONT15x", "HG003_15xactual.cleaned.cram"),
]

lines = [HEADER]
lane = 0
for sr_label, sr_file in SR_LEVELS:
    for ont_label, ont_file in ONT_LEVELS:
        exp = f"{sr_label}-{ont_label}"
        r1 = f"{ILMN_BASE}/{sr_file}_R1.fastq.gz"
        r2 = f"{ILMN_BASE}/{sr_file}_R2.fastq.gz"
        ont_cram = f"{ONT_BASE}/{ont_file}"
        # Start from template, override specific columns
        cols = [""] * NCOLS
        cols[0] = "HIOa"       # RUNID
        cols[1] = "HG003"      # SAMPLEID
        cols[2] = exp           # EXPERIMENTID
        cols[3] = str(lane)     # LANEID
        cols[4] = "D0"         # BARCODEID
        cols[5] = "PF"         # LIBPREP
        cols[6] = "ILMN"      # SEQ_VENDOR
        cols[7] = "NOVASEQ"   # SEQ_PLATFORM
        cols[8] = r1           # ILMN_R1_PATH
        cols[9] = r2           # ILMN_R2_PATH
        cols[18] = "posControl"  # SAMPLEUSE
        cols[19] = "na"        # BWA_KMER
        cols[20] = "WGS"       # DEEP_MODEL
        cols[24] = ont_cram    # ONT_CRAM
        cols[25] = "ont"       # ONT_CRAM_ALIGNER
        cols[26] = "sentdont"  # ONT_CRAM_SNV_CALLER
        lines.append("\t".join(cols))
        lane += 1

out = ".test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/test3x3_units.tsv"
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"Wrote {lane} units to {out}")

