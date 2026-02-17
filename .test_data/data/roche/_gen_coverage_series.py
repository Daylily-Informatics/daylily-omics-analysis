#!/usr/bin/env python3
"""Generate Roche SBX Duplex coverage series TSV files."""
import os

COLS = [
    "RUNID", "SAMPLEID", "EXPERIMENTID", "LANEID", "BARCODEID", "LIBPREP",
    "SEQ_VENDOR", "SEQ_PLATFORM", "ILMN_R1_PATH", "ILMN_R2_PATH",
    "PACBIO_R1_PATH", "PACBIO_R2_PATH", "ONT_R1_PATH", "ONT_R2_PATH",
    "UG_R1_PATH", "UG_R2_PATH", "SUBSAMPLE_PCT", "ILMN_TRIM_READ_LENGTH",
    "SAMPLEUSE", "BWA_KMER", "DEEP_MODEL", "ULTIMA_CRAM",
    "ULTIMA_CRAM_ALIGNER", "ULTIMA_CRAM_SNV_CALLER", "ONT_CRAM",
    "ONT_CRAM_ALIGNER", "ONT_CRAM_SNV_CALLER", "PB_BAM", "PB_BAM_ALIGNER",
    "PB_BAM_SNV_CALLER", "ROCHE_BAM", "ROCHE_BAM_ALIGNER",
    "ROCHE_BAM_SNV_CALLER", "ROCHE_DOWNSAMPLE_RATIO",
]

SCOLS = [
    "SAMPLEID", "SAMPLESOURCE", "SAMPLECLASS", "BIOLOGICAL_SEX",
    "CONCORDANCE_CONTROL_PATH", "IS_POSITIVE_CONTROL", "IS_NEGATIVE_CONTROL",
    "SAMPLE_TYPE", "TUM_NRM_SAMPLEID_MATCH", "EXTERNAL_SAMPLE_ID",
    "N_X", "N_Y", "TRUTH_DATA_DIR",
]

BASE_COV = 58.15
BAM_DIR = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/roche/091025_webinar_data_giab_bam_bwa"
TRUTH_BASE = "/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1"
OUTDIR = os.path.dirname(os.path.abspath(__file__))
T = "\t"


def make_row(sample, cov):
    ratio = min(round(cov / BASE_COV, 3), 1.0)
    bam = f"{BAM_DIR}/{sample}.bam"
    vals = {
        "RUNID": "R0", "SAMPLEID": sample, "EXPERIMENTID": f"{cov}x",
        "LANEID": "0", "BARCODEID": "D0", "LIBPREP": "PCR-FREE",
        "SEQ_VENDOR": "ROCHE", "SEQ_PLATFORM": "SBX-DUPLEX",
        "SAMPLEUSE": "posControl", "BWA_KMER": "19", "DEEP_MODEL": "WGS",
        "ROCHE_BAM": bam, "ROCHE_BAM_ALIGNER": "roche",
        "ROCHE_BAM_SNV_CALLER": "rochehc",
        "ROCHE_DOWNSAMPLE_RATIO": str(ratio),
    }
    return T.join(vals.get(c, "") for c in COLS)


def make_srow(sample):
    truth = f"{TRUTH_BASE}/{sample}/"
    vals = {
        "SAMPLEID": sample, "SAMPLESOURCE": "blood", "SAMPLECLASS": "research",
        "BIOLOGICAL_SEX": "male", "CONCORDANCE_CONTROL_PATH": truth,
        "IS_POSITIVE_CONTROL": "true", "IS_NEGATIVE_CONTROL": "false",
        "SAMPLE_TYPE": "gdna", "TUM_NRM_SAMPLEID_MATCH": "na",
        "EXTERNAL_SAMPLE_ID": sample, "N_X": "1", "N_Y": "1",
        "TRUTH_DATA_DIR": truth,
    }
    return T.join(vals.get(c, "") for c in SCOLS)


def write_units(path, sample, covs):
    with open(path, "w") as f:
        f.write(T.join(COLS) + "\n")
        for c in covs:
            f.write(make_row(sample, c) + "\n")
    print(f"Wrote {path} ({len(covs)} rows)")


def write_samples(path, sample):
    with open(path, "w") as f:
        f.write(T.join(SCOLS) + "\n")
        f.write(make_srow(sample) + "\n")
    print(f"Wrote {path} (1 row)")


write_units(os.path.join(OUTDIR, "coverage_series_hg003_units.tsv"), "HG003",
            [1, 3, 5, 7, 10, 15, 20, 30, 40])
write_samples(os.path.join(OUTDIR, "coverage_series_hg003_samples.tsv"), "HG003")
write_units(os.path.join(OUTDIR, "coverage_series_hg002_units.tsv"), "HG002",
            [1, 3, 5, 7, 10, 15, 20, 30, 40, 50])
write_samples(os.path.join(OUTDIR, "coverage_series_hg002_samples.tsv"), "HG002")

print("\nVerifying column counts...")
for fn in ["coverage_series_hg003_units.tsv", "coverage_series_hg002_units.tsv",
           "coverage_series_hg003_samples.tsv", "coverage_series_hg002_samples.tsv"]:
    fp = os.path.join(OUTDIR, fn)
    with open(fp) as f:
        lines = f.readlines()
    exp = 34 if "units" in fn else 13
    for i, line in enumerate(lines):
        nc = len(line.rstrip("\n").split(T))
        ok = "OK" if nc == exp else f"MISMATCH (got {nc} expected {exp})"
        if i <= 1:
            label = "header" if i == 0 else "row1"
            print(f"  {fn} {label}: {nc} cols - {ok}")

