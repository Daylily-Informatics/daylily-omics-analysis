#!/usr/bin/env python3
"""Generate manifest files for downsample_series test data."""

import os

BASE_DIR = ".test_data/data/agbt_2026/downsample_series"

HEADER = "RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\tPACBIO_R1_PATH\tPACBIO_R2_PATH\tONT_R1_PATH\tONT_R2_PATH\tUG_R1_PATH\tUG_R2_PATH\tSUBSAMPLE_PCT\tILMN_TRIM_READ_LENGTH\tSAMPLEUSE\tBWA_KMER\tDEEP_MODEL\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\tULTIMA_CRAM_SNV_CALLER\tONT_CRAM\tONT_CRAM_ALIGNER\tONT_CRAM_SNV_CALLER\tPB_BAM\tPB_BAM_ALIGNER\tPB_BAM_SNV_CALLER"

# Base paths
ILMN_STD = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled"
ILMN_SCRATCH = "/fsx/scratch/downsamples/ilmn/HG003"
UG_BASE = "/fsx/scratch/downsamples/ultima_cleaned_hg38_broad/HG003"
ONT_BASE = "/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003"
PB_BASE = "/fsx/scratch/downsamples/pacbio/HG003/R0-HG003-D0-0-D0"

# Available coverages per platform
ILMN_COVS = ["0.1x", "0.4x", "1x", "1.5x", "3x", "5x", "7x", "10x", "15x", "20x", "40x", "50x"]
UG_COVS = ["1x", "3x", "5x", "7x", "10x", "15x", "20x", "30x", "40x", "50x"]
ONT_COVS = ["1x", "3x", "7x"]
PB_COVS = ["0p1x", "0p5x", "1p0x", "1p5x", "3p0x", "5p0x", "7p0x", "10p0x", "15p0x", "20p0x", "30p0x"]

# ILMN coverages that are in scratch vs standard
ILMN_SCRATCH_COVS = {"7x", "40x", "50x"}

def get_ilmn_paths(cov):
    if cov in ILMN_SCRATCH_COVS:
        base = f"{ILMN_SCRATCH}/{cov}"
        return f"{base}/HG003_{cov}_R1.fastq.gz", f"{base}/HG003_{cov}_R2.fastq.gz"
    return f"{ILMN_STD}/HG003_{cov}_R1.fastq.gz", f"{ILMN_STD}/HG003_{cov}_R2.fastq.gz"

def write_ilmn_solo():
    for cov in ILMN_COVS:
        r1, r2 = get_ilmn_paths(cov)
        fname = f"{BASE_DIR}/ilmn-solo/HG003_{cov}.units.tsv"
        with open(fname, "w") as f:
            f.write(HEADER + "\n")
            f.write(f"R0\tHG003\tX1\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t{r1}\t{r2}\t\t\t\t\t\t\t\t\tposControl\t19\t\t\t\t\t\t\t\t\t\t\n")
        print(f"Created {fname}")

def write_ug_solo():
    for cov in UG_COVS:
        cram = f"{UG_BASE}/HG003_{cov}.cleaned.cram"
        fname = f"{BASE_DIR}/ug-solo/HG003_{cov}.units.tsv"
        with open(fname, "w") as f:
            f.write(HEADER + "\n")
            f.write(f"R0\tHG003\tX1\t0\tD0\tPCR-FREE\tUG\tULTIMA\t\t\t\t\t\t\t\t\t\t\tresearch\t19\t\t{cram}\tug\tug\t\t\t\t\t\t\n")
        print(f"Created {fname}")

def write_ont_solo():
    for cov in ONT_COVS:
        cram = f"{ONT_BASE}/HG003_{cov}.cleaned.cram"
        fname = f"{BASE_DIR}/ont-solo/HG003_{cov}.units.tsv"
        with open(fname, "w") as f:
            f.write(HEADER + "\n")
            f.write(f"R0\tHG003\tD0\t0\tD0\tPCR-FREE\tONT\tPROMETHION\tna\tna\tna\tna\tna\tna\tna\tna\tna\tna\tresearch\t19\tONT_R104\tna\tna\tna\t{cram}\tont\tsentdont\tna\tna\tna\n")
        print(f"Created {fname}")

def write_pb_solo():
    for cov in PB_COVS:
        bam = f"{PB_BASE}/{cov}/HG003_{cov}.bam"
        fname = f"{BASE_DIR}/pb-solo/HG003_{cov}.units.tsv"
        with open(fname, "w") as f:
            f.write(HEADER + "\n")
            f.write(f"R0\tHG003\tD0\t0\tD0\tPCR-FREE\tPB\tSEQUEL2\tna\tna\tna\tna\tna\tna\tna\tna\tna\tna\tresearch\t19\tPBR\tna\tna\tna\tna\tna\tna\t{bam}\tsentmm2\tsentdpb\n")
        print(f"Created {fname}")

def write_sentdhio():
    # Hybrid ILMN+ONT - need matching coverages (ONT only has 1x, 3x, 7x)
    for cov in ONT_COVS:
        # Map ONT cov to ILMN cov format (ONT uses 1x, ILMN uses 1x)
        ilmn_cov = cov
        r1, r2 = get_ilmn_paths(ilmn_cov)
        ont_cram = f"{ONT_BASE}/HG003_{cov}.cleaned.cram"
        fname = f"{BASE_DIR}/sentdhio/HG003_{cov}.units.tsv"
        with open(fname, "w") as f:
            f.write(HEADER + "\n")
            f.write(f"R0\tHG003\tX1\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t{r1}\t{r2}\t\t\t\t\t\t\t\t\tposControl\t19\tONT_R104\t\t\t\t{ont_cram}\tont\tsentdont\t\t\t\n")
        print(f"Created {fname}")

if __name__ == "__main__":
    write_ilmn_solo()
    write_ug_solo()
    write_ont_solo()
    write_pb_solo()
    write_sentdhio()
    print("\nDone! All manifest files created.")

