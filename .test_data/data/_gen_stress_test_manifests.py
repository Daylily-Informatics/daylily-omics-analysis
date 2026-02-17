#!/usr/bin/env python3
"""
Generate samples.tsv and units.tsv files for HG003 stress tests.

Single platform tests (3x coverage):
- ont, ilmn, pb, ug, roche

Hybrid tests (3x coverage by 2 platforms):
- ilmn_ont, ilmn_pb, ug_ont, ug_pb, roche_ont, roche_pb
"""
import os
from pathlib import Path

# Base paths
BASE = Path(".test_data/data")
STRESS_TESTS = BASE / "stress_tests"
HYBRID = BASE / "hybrid"

# HG003 samples.tsv content (same for all)
SAMPLES_HEADER = "SAMPLEID\tSAMPLESOURCE\tSAMPLECLASS\tBIOLOGICAL_SEX\tCONCORDANCE_CONTROL_PATH\tIS_POSITIVE_CONTROL\tIS_NEGATIVE_CONTROL\tSAMPLE_TYPE\tTUM_NRM_SAMPLEID_MATCH\tEXTERNAL_SAMPLE_ID\tN_X\tN_Y\tTRUTH_DATA_DIR"
SAMPLES_ROW = "HG003\tblood\tresearch\tmale\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\ttrue\tfalse\tgdna\t\tHG003\t1\t1\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/"

# Units header (standard columns + Roche columns)
UNITS_HEADER = "RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\tPACBIO_R1_PATH\tPACBIO_R2_PATH\tONT_R1_PATH\tONT_R2_PATH\tUG_R1_PATH\tUG_R2_PATH\tSUBSAMPLE_PCT\tILMN_TRIM_READ_LENGTH\tSAMPLEUSE\tBWA_KMER\tDEEP_MODEL\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\tULTIMA_CRAM_SNV_CALLER\tONT_CRAM\tONT_CRAM_ALIGNER\tONT_CRAM_SNV_CALLER\tPB_BAM\tPB_BAM_ALIGNER\tPB_BAM_SNV_CALLER\tROCHE_BAM\tROCHE_BAM_ALIGNER\tROCHE_BAM_SNV_CALLER\tROCHE_DOWNSAMPLE_RATIO"

# Data paths
ILMN_R1_3X = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"
ILMN_R2_3X = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R2.fastq.gz"
ONT_CRAM_3X = "/fsx/scratch/downsamples/ont_cleaned_hg38/HG003/HG003_3x.cleaned.cram"
UG_CRAM_3X = "/fsx/scratch/downsamples/ultima_cleaned_hg38_broad/HG003/HG003_3x.cleaned.cram"
PB_BAM_3X = "/fsx/scratch/downsamples/pacbio/HG003/R0-HG003-D0-0-D0/3p0x/HG003_3p0x.bam"
ROCHE_BAM = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/roche/091025_webinar_data_giab_bam_bwa/HG003.bam"
ROCHE_DOWNSAMPLE_3X = "0.069"

def write_samples(path):
    """Write samples.tsv file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w') as f:
        f.write(SAMPLES_HEADER + "\n")
        f.write(SAMPLES_ROW + "\n")
    print(f"  Created: {path}")

def write_units(path, row_data):
    """Write units.tsv file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w') as f:
        f.write(UNITS_HEADER + "\n")
        f.write(row_data + "\n")
    print(f"  Created: {path}")

def make_row(vendor, platform, ilmn_r1="", ilmn_r2="", ug_cram="", ug_aln="", ug_caller="",
             ont_cram="", ont_aln="", ont_caller="", pb_bam="", pb_aln="", pb_caller="",
             roche_bam="", roche_aln="", roche_caller="", roche_ds="", deep_model="WGS"):
    """Build a units row."""
    return f"R0\tHG003\t3x\t0\tD0\tPCR-FREE\t{vendor}\t{platform}\t{ilmn_r1}\t{ilmn_r2}\t\t\t\t\t\t\t\t\tposControl\t19\t{deep_model}\t{ug_cram}\t{ug_aln}\t{ug_caller}\t{ont_cram}\t{ont_aln}\t{ont_caller}\t{pb_bam}\t{pb_aln}\t{pb_caller}\t{roche_bam}\t{roche_aln}\t{roche_caller}\t{roche_ds}"

# Single platform configs
SINGLE_PLATFORMS = {
    "ont": make_row("ONT", "PROMETHION", ont_cram=ONT_CRAM_3X, ont_aln="ont", ont_caller="sentdont", deep_model="ONT_R104"),
    "ilmn": make_row("ILMN", "NOVASEQ", ilmn_r1=ILMN_R1_3X, ilmn_r2=ILMN_R2_3X),
    "pb": make_row("PACBIO", "REVIO", pb_bam=PB_BAM_3X, pb_aln="sentmm2", pb_caller="sentdpb"),
    "ug": make_row("UG", "ULTIMA", ug_cram=UG_CRAM_3X, ug_aln="ug", ug_caller="ug"),
    "roche": make_row("ROCHE", "SBX-DUPLEX", roche_bam=ROCHE_BAM, roche_aln="roche", roche_caller="rochehc", roche_ds=ROCHE_DOWNSAMPLE_3X),
}

# Hybrid configs (SR + LR)
HYBRID_PLATFORMS = {
    "ilmn_ont": make_row("ILMN", "NOVASEQ", ilmn_r1=ILMN_R1_3X, ilmn_r2=ILMN_R2_3X,
                          ont_cram=ONT_CRAM_3X, ont_aln="ont", ont_caller="sentdont", deep_model="ONT_R104"),
    "ilmn_pb": make_row("ILMN", "NOVASEQ", ilmn_r1=ILMN_R1_3X, ilmn_r2=ILMN_R2_3X,
                         pb_bam=PB_BAM_3X, pb_aln="sentmm2", pb_caller="sentdpb"),
    "ug_ont": make_row("UG", "ULTIMA", ug_cram=UG_CRAM_3X, ug_aln="ug", ug_caller="ug",
                        ont_cram=ONT_CRAM_3X, ont_aln="ont", ont_caller="sentdont", deep_model="ONT_R104"),
    "ug_pb": make_row("UG", "ULTIMA", ug_cram=UG_CRAM_3X, ug_aln="ug", ug_caller="ug",
                       pb_bam=PB_BAM_3X, pb_aln="sentmm2", pb_caller="sentdpb"),
    "roche_ont": make_row("ROCHE", "SBX-DUPLEX", roche_bam=ROCHE_BAM, roche_aln="roche", roche_caller="rochehc", roche_ds=ROCHE_DOWNSAMPLE_3X,
                           ont_cram=ONT_CRAM_3X, ont_aln="ont", ont_caller="sentdont", deep_model="ONT_R104"),
    "roche_pb": make_row("ROCHE", "SBX-DUPLEX", roche_bam=ROCHE_BAM, roche_aln="roche", roche_caller="rochehc", roche_ds=ROCHE_DOWNSAMPLE_3X,
                          pb_bam=PB_BAM_3X, pb_aln="sentmm2", pb_caller="sentdpb"),
}

def main():
    print("Creating single-platform stress test manifests...")
    for plat, row in SINGLE_PLATFORMS.items():
        base_path = STRESS_TESTS / plat / "hg003" / "3x"
        write_samples(base_path / "samples.tsv")
        write_units(base_path / "units.tsv", row)
    
    print("\nCreating hybrid stress test manifests...")
    for combo, row in HYBRID_PLATFORMS.items():
        base_path = HYBRID / combo / "hg003" / "3x"
        write_samples(base_path / "samples.tsv")
        write_units(base_path / "units.tsv", row)
    
    print("\nDone! Created all manifest files.")

if __name__ == "__main__":
    main()

