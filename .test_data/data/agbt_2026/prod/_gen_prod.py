#!/usr/bin/env python3
"""Generate AGBT 2026 prod TSV configs for Illumina-only and hybrid Illumina+PacBio."""
import os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

SAMPLES_HEADER = "\t".join([
    "SAMPLEID", "SAMPLESOURCE", "SAMPLECLASS", "BIOLOGICAL_SEX",
    "CONCORDANCE_CONTROL_PATH", "IS_POSITIVE_CONTROL", "IS_NEGATIVE_CONTROL",
    "SAMPLE_TYPE", "TUM_NRM_SAMPLEID_MATCH", "EXTERNAL_SAMPLE_ID",
    "N_X", "N_Y", "TRUTH_DATA_DIR",
])
TRUTH = "/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/"
SAMPLES_ROW = "\t".join([
    "HG003", "blood", "research", "male", TRUTH,
    "true", "false", "gdna", "", "HG003", "1", "1", TRUTH,
])

COLS_30 = [
    "RUNID", "SAMPLEID", "EXPERIMENTID", "LANEID", "BARCODEID", "LIBPREP",
    "SEQ_VENDOR", "SEQ_PLATFORM", "ILMN_R1_PATH", "ILMN_R2_PATH",
    "PACBIO_R1_PATH", "PACBIO_R2_PATH", "ONT_R1_PATH", "ONT_R2_PATH",
    "UG_R1_PATH", "UG_R2_PATH", "SUBSAMPLE_PCT", "ILMN_TRIM_READ_LENGTH",
    "SAMPLEUSE", "BWA_KMER", "DEEP_MODEL", "ULTIMA_CRAM", "ULTIMA_CRAM_ALIGNER",
    "ULTIMA_CRAM_SNV_CALLER", "ONT_CRAM", "ONT_CRAM_ALIGNER", "ONT_CRAM_SNV_CALLER",
    "PB_BAM", "PB_BAM_ALIGNER", "PB_BAM_SNV_CALLER",
]
ROCHE_COLS = ["ROCHE_BAM", "ROCHE_BAM_ALIGNER", "ROCHE_BAM_SNV_CALLER", "ROCHE_DOWNSAMPLE_RATIO"]

DS = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007"
PB = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/pacbio/HG003/R0-HG003-D0-0-D0"

ILMN_COVS = ["1x", "3x", "5x", "7x", "10x", "15x", "20x", "30x", "40x"]
PB_COVS =   ["1x", "3x", "5x", "7x", "10x", "15x", "20x", "30x"]

def fq(cov, read):
    if cov == "30x":
        return f"{DS}/HG003_30x_R{read}.fastq.gz"
    return f"{DS}/downsampled/HG003_{cov}_R{read}.fastq.gz"

def pb_bam(cov):
    label = cov.replace("x", "p0x")
    return f"{PB}/{label}/HG003_{label}.bam"

def ilmn_row(cov, ncols):
    d = {c: "" for c in (COLS_30 + ROCHE_COLS)[:ncols]}
    d["RUNID"], d["SAMPLEID"], d["EXPERIMENTID"] = "R0", "HG003", cov
    d["LANEID"], d["BARCODEID"] = "0", "D0"
    d["LIBPREP"], d["SEQ_VENDOR"], d["SEQ_PLATFORM"] = "PCR-FREE", "ILMN", "NOVASEQ"
    d["ILMN_R1_PATH"], d["ILMN_R2_PATH"] = fq(cov, 1), fq(cov, 2)
    d["SAMPLEUSE"], d["BWA_KMER"], d["DEEP_MODEL"] = "posControl", "19", "WGS"
    return "\t".join(d[c] for c in (COLS_30 + ROCHE_COLS)[:ncols])

def hybrid_row(cov):
    d = {c: "" for c in COLS_30 + ROCHE_COLS}
    d["RUNID"], d["SAMPLEID"], d["EXPERIMENTID"] = "R0", "HG003", cov
    d["LANEID"], d["BARCODEID"] = "0", "D0"
    d["LIBPREP"], d["SEQ_VENDOR"], d["SEQ_PLATFORM"] = "PCR-FREE", "ILMN", "NOVASEQ"
    d["ILMN_R1_PATH"], d["ILMN_R2_PATH"] = fq(cov, 1), fq(cov, 2)
    d["SAMPLEUSE"], d["BWA_KMER"], d["DEEP_MODEL"] = "posControl", "19", "WGS"
    d["PB_BAM"], d["PB_BAM_ALIGNER"], d["PB_BAM_SNV_CALLER"] = pb_bam(cov), "sentmm2", "sentdpb"
    return "\t".join(d[c] for c in COLS_30 + ROCHE_COLS)

def write(path, header_cols, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\t".join(header_cols) + "\n")
        for r in rows:
            f.write(r + "\n")

# Task 1: Illumina-only (30 columns)
idir = os.path.join(SCRIPT_DIR, "ilmn")
write(f"{idir}/samples.tsv", SAMPLES_HEADER.split("\t"), [SAMPLES_ROW])
write(f"{idir}/units.tsv", COLS_30, [ilmn_row(c, 30) for c in ILMN_COVS])

# Task 2: Hybrid Illumina+PacBio (34 columns)
hdir = os.path.join(SCRIPT_DIR, "hybrid", "ilmn_pb")
write(f"{hdir}/samples.tsv", SAMPLES_HEADER.split("\t"), [SAMPLES_ROW])
write(f"{hdir}/units.tsv", COLS_30 + ROCHE_COLS, [hybrid_row(c) for c in PB_COVS])

# Verify
ok = True
for tag, p, ec, er in [
    ("ilmn/units", f"{idir}/units.tsv", 30, 10),
    ("ilmn/samples", f"{idir}/samples.tsv", 13, 2),
    ("hybrid/units", f"{hdir}/units.tsv", 34, 9),
    ("hybrid/samples", f"{hdir}/samples.tsv", 13, 2),
]:
    lines = [l for l in open(p).read().splitlines() if l.strip()]
    for i, l in enumerate(lines):
        nc = len(l.split("\t"))
        if nc != ec:
            print(f"FAIL {tag} line {i+1}: {nc} cols, expected {ec}", file=sys.stderr)
            ok = False
    if len(lines) != er:
        print(f"FAIL {tag}: {len(lines)} lines, expected {er}", file=sys.stderr)
        ok = False
    print(f"OK  {tag}: {len(lines)} lines, {ec} cols")
sys.exit(0 if ok else 1)

