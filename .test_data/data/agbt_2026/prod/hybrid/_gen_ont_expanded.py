#!/usr/bin/env python3
"""Generate AGBT 2026 expanded ILMN+ONT and Ultima+ONT hybrid coverage grid TSVs.

Coverage combinations:
  SR (ILMN/Ultima): 1, 3, 5, 7, 10, 15, 20, 30, 40 (9 levels)
  LR (ONT):         1, 3, 7, 10, 15, 20, 30        (7 levels)
  Total:            9 * 7 = 63 samples per pairing
"""
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Coverage levels
SR_COVS = [1, 3, 5, 7, 10, 15, 20, 30, 40]
ONT_COVS = [1, 3, 7, 10, 15, 20, 30]

# Header for samples.tsv
SAMPLES_HEADER = [
    "SAMPLEID", "SAMPLESOURCE", "SAMPLECLASS", "BIOLOGICAL_SEX",
    "CONCORDANCE_CONTROL_PATH", "IS_POSITIVE_CONTROL", "IS_NEGATIVE_CONTROL",
    "SAMPLE_TYPE", "TUM_NRM_SAMPLEID_MATCH", "EXTERNAL_SAMPLE_ID",
    "N_X", "N_Y", "TRUTH_DATA_DIR",
]

# Header for units.tsv (30 columns, no ROCHE columns)
UNITS_HEADER = [
    "RUNID", "SAMPLEID", "EXPERIMENTID", "LANEID", "BARCODEID", "LIBPREP",
    "SEQ_VENDOR", "SEQ_PLATFORM", "ILMN_R1_PATH", "ILMN_R2_PATH",
    "PACBIO_R1_PATH", "PACBIO_R2_PATH", "ONT_R1_PATH", "ONT_R2_PATH",
    "UG_R1_PATH", "UG_R2_PATH", "SUBSAMPLE_PCT", "ILMN_TRIM_READ_LENGTH",
    "SAMPLEUSE", "BWA_KMER", "DEEP_MODEL", "ULTIMA_CRAM", "ULTIMA_CRAM_ALIGNER",
    "ULTIMA_CRAM_SNV_CALLER", "ONT_CRAM", "ONT_CRAM_ALIGNER", "ONT_CRAM_SNV_CALLER",
    "PB_BAM", "PB_BAM_ALIGNER", "PB_BAM_SNV_CALLER",
]

TRUTH_HG38 = "/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/"
TRUTH_HG38_BROAD = "/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38_broad/controls/giab/snv/v4.2.1/HG003/"

# File path templates
ILMN_R1 = "/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_{cov}x_R1.fastq.gz"
ILMN_R2 = "/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_{cov}x_R2.fastq.gz"
ONT_CRAM_HG38 = "/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003/HG003_{cov}x.cleaned.cram"
UG_CRAM_HG38_BROAD = "/fsx/scratch/downsamples/ultima_cleaned_hg38_broad/HG003/HG003_{cov}x.cleaned.cram"


def write_tsv(path: str, header: list, rows: list):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\t".join(header) + "\n")
        for row in rows:
            f.write("\t".join(str(c) for c in row) + "\n")
    print(f"Wrote {path} ({len(rows)} rows)")


def experiment_id(sr_cov: int, ont_cov: int) -> str:
    """Generate experiment ID encoding both coverages."""
    return f"SR{sr_cov}x-ONT{ont_cov}x"


def ilmn_ont_units_row(sr_cov: int, ont_cov: int, lane_id: int) -> list:
    """Generate ILMN+ONT hybrid units row."""
    return [
        "HIOa",  # RUNID
        "HG003",  # SAMPLEID
        experiment_id(sr_cov, ont_cov),  # EXPERIMENTID
        lane_id,  # LANEID
        "D0",  # BARCODEID
        "PF",  # LIBPREP
        "ILMN",  # SEQ_VENDOR
        "NOVASEQ",  # SEQ_PLATFORM
        ILMN_R1.format(cov=sr_cov),  # ILMN_R1_PATH
        ILMN_R2.format(cov=sr_cov),  # ILMN_R2_PATH
        "", "", "", "", "", "",  # PACBIO/ONT/UG paths (empty)
        "posControl",  # SUBSAMPLE_PCT
        "na",  # ILMN_TRIM_READ_LENGTH
        "WGS",  # SAMPLEUSE
        "", "",  # BWA_KMER, DEEP_MODEL
        "", "", "",  # ULTIMA_CRAM fields (empty for ILMN)
        ONT_CRAM_HG38.format(cov=ont_cov),  # ONT_CRAM
        "ont",  # ONT_CRAM_ALIGNER
        "sentdont",  # ONT_CRAM_SNV_CALLER
        "", "", "",  # PB_BAM fields (empty)
    ]


def ilmn_ont_samples_row() -> list:
    """Generate ILMN+ONT hybrid samples row (single HG003)."""
    return [
        "HG003", "blood", "research", "male", TRUTH_HG38,
        "true", "false", "gdna", "", "HG003", "1", "1", TRUTH_HG38,
    ]


def ug_ont_units_row(sr_cov: int, ont_cov: int, lane_id: int) -> list:
    """Generate Ultima+ONT hybrid units row."""
    return [
        "HUOa",  # RUNID
        "HG003",  # SAMPLEID
        experiment_id(sr_cov, ont_cov),  # EXPERIMENTID
        lane_id,  # LANEID
        "D0",  # BARCODEID
        "PF",  # LIBPREP
        "UG",  # SEQ_VENDOR
        "ULTIMA",  # SEQ_PLATFORM
        "", "",  # ILMN paths (empty)
        "", "", "", "", "", "",  # PACBIO/ONT/UG raw paths (empty)
        "posControl",  # SUBSAMPLE_PCT
        "na",  # ILMN_TRIM_READ_LENGTH
        "WGS",  # SAMPLEUSE
        "", "",  # BWA_KMER, DEEP_MODEL
        UG_CRAM_HG38_BROAD.format(cov=sr_cov),  # ULTIMA_CRAM
        "ug",  # ULTIMA_CRAM_ALIGNER
        "ug",  # ULTIMA_CRAM_SNV_CALLER
        ONT_CRAM_HG38.format(cov=ont_cov),  # ONT_CRAM (hg38_broad aligned)
        "ont",  # ONT_CRAM_ALIGNER
        "sentdont",  # ONT_CRAM_SNV_CALLER
        "", "", "",  # PB_BAM fields (empty)
    ]


def ug_ont_samples_row() -> list:
    """Generate Ultima+ONT hybrid samples row (single HG003)."""
    return [
        "HG003", "blood", "research", "male", TRUTH_HG38_BROAD,
        "true", "false", "gdna", "", "HG003", "1", "1", TRUTH_HG38_BROAD,
    ]


def main():
    # Generate ILMN+ONT expanded
    ilmn_ont_dir = os.path.join(SCRIPT_DIR, "ilmn_ont_expanded")
    ilmn_units = []
    lane = 0
    for sr in SR_COVS:
        for ont in ONT_COVS:
            ilmn_units.append(ilmn_ont_units_row(sr, ont, lane))
            lane += 1

    write_tsv(f"{ilmn_ont_dir}/units.tsv", UNITS_HEADER, ilmn_units)
    write_tsv(f"{ilmn_ont_dir}/samples.tsv", SAMPLES_HEADER, [ilmn_ont_samples_row()])

    # Generate Ultima+ONT expanded
    ug_ont_dir = os.path.join(SCRIPT_DIR, "ultima_ont_expanded")
    ug_units = []
    lane = 0
    for sr in SR_COVS:
        for ont in ONT_COVS:
            ug_units.append(ug_ont_units_row(sr, ont, lane))
            lane += 1

    write_tsv(f"{ug_ont_dir}/units.tsv", UNITS_HEADER, ug_units)
    write_tsv(f"{ug_ont_dir}/samples.tsv", SAMPLES_HEADER, [ug_ont_samples_row()])

    print(f"\nGenerated {len(ilmn_units)} ILMN+ONT combinations")
    print(f"Generated {len(ug_units)} Ultima+ONT combinations")


if __name__ == "__main__":
    main()

