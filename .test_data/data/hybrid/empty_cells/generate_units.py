#!/usr/bin/env python3
"""Generate units.tsv and samples.tsv for hybrid coverage titration matrices."""

import os

# Coverage levels
SR_COVS = [1, 3, 5, 7, 10, 15, 20, 30, 40]  # Short-read
LR_COVS = [0.5, 1, 3, 5, 7, 10, 15, 20, 30]  # Long-read

# TSV header columns
HEADER = [
    "RUNID", "SAMPLEID", "EXPERIMENTID", "LANEID", "BARCODEID", "LIBPREP",
    "SEQ_VENDOR", "SEQ_PLATFORM", "ILMN_R1_PATH", "ILMN_R2_PATH",
    "PACBIO_R1_PATH", "PACBIO_R2_PATH", "ONT_R1_PATH", "ONT_R2_PATH",
    "UG_R1_PATH", "UG_R2_PATH", "SUBSAMPLE_PCT", "ILMN_TRIM_READ_LENGTH",
    "SAMPLEUSE", "BWA_KMER", "DEEP_MODEL", "ULTIMA_CRAM", "ULTIMA_CRAM_ALIGNER",
    "ULTIMA_CRAM_SNV_CALLER", "ONT_CRAM", "ONT_CRAM_ALIGNER", "ONT_CRAM_SNV_CALLER",
    "PB_BAM", "PB_BAM_ALIGNER", "PB_BAM_SNV_CALLER", "ROCHE_BAM",
    "ROCHE_BAM_ALIGNER", "ROCHE_BAM_SNV_CALLER", "ROCHE_DOWNSAMPLE_RATIO"
]

SAMPLES_HEADER = [
    "SAMPLEID", "SAMPLESOURCE", "SAMPLECLASS", "BIOLOGICAL_SEX",
    "CONCORDANCE_CONTROL_PATH", "IS_POSITIVE_CONTROL", "IS_NEGATIVE_CONTROL",
    "SAMPLE_TYPE", "TUM_NRM_SAMPLEID_MATCH", "EXTERNAL_SAMPLE_ID", "N_X", "N_Y",
    "TRUTH_DATA_DIR"
]

# Path templates
ILMN_R1 = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_{cov}x_R1.fastq.gz"
ILMN_R2 = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_{cov}x_R2.fastq.gz"
ULTIMA_CRAM = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_{cov}x.cleaned.cram"
ONT_CRAM = "/fsx/scratch/downsamples/ont_cleaned_hg38_broad/HG003/HG003_{cov}x.cleaned.cram"
PB_BAM = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/pacbio/HG003/R0-HG003-D0-0-D0/{cov}p0x/HG003_{cov}p0x.bam"

def fmt_cov(c):
    """Format coverage for paths (handle 0.5 -> 0p5)."""
    if c == int(c):
        return str(int(c))
    return str(c).replace(".", "p")

def generate_units(hybrid_type):
    """Generate units.tsv rows for a hybrid type."""
    rows = []
    row_idx = 0
    
    for sr_cov in SR_COVS:
        for lr_cov in LR_COVS:
            row = {col: "" for col in HEADER}
            row["RUNID"] = f"R{row_idx}"
            row["SAMPLEID"] = "HG003"
            row["EXPERIMENTID"] = f"SR{sr_cov}x-LR{fmt_cov(lr_cov)}x"
            row["LANEID"] = str(row_idx)
            row["BARCODEID"] = "D0"
            row["LIBPREP"] = "PCR-FREE"
            row["SAMPLEUSE"] = "posControl"
            row["BWA_KMER"] = "19"
            
            if hybrid_type in ("hiomr", "hipmr"):  # ILMN primary
                row["SEQ_VENDOR"] = "ILMN"
                row["SEQ_PLATFORM"] = "NOVASEQ"
                row["ILMN_R1_PATH"] = ILMN_R1.format(cov=sr_cov)
                row["ILMN_R2_PATH"] = ILMN_R2.format(cov=sr_cov)
            else:  # Ultima primary (huomr, hupmr)
                row["SEQ_VENDOR"] = "UG"
                row["SEQ_PLATFORM"] = "ULTIMA"
                row["ULTIMA_CRAM"] = ULTIMA_CRAM.format(cov=sr_cov)
                row["ULTIMA_CRAM_ALIGNER"] = "ug"
                row["ULTIMA_CRAM_SNV_CALLER"] = "ug"
            
            if hybrid_type in ("hiomr", "huomr"):  # ONT secondary
                row["DEEP_MODEL"] = "ONT_R104"
                row["ONT_CRAM"] = ONT_CRAM.format(cov=fmt_cov(lr_cov))
                row["ONT_CRAM_ALIGNER"] = "ont"
                row["ONT_CRAM_SNV_CALLER"] = "sentdont"
            else:  # PacBio secondary (hipmr, hupmr)
                row["DEEP_MODEL"] = "WGS"
                row["PB_BAM"] = PB_BAM.format(cov=fmt_cov(lr_cov))
                row["PB_BAM_ALIGNER"] = "sentmm2"
                row["PB_BAM_SNV_CALLER"] = "sentdpb"
            
            rows.append(row)
            row_idx += 1
    
    return rows

def write_units_tsv(hybrid_type, out_dir):
    """Write units.tsv for hybrid type."""
    rows = generate_units(hybrid_type)
    os.makedirs(out_dir, exist_ok=True)
    
    with open(os.path.join(out_dir, "units.tsv"), "w") as f:
        f.write("\t".join(HEADER) + "\n")
        for row in rows:
            f.write("\t".join(row[col] for col in HEADER) + "\n")
    print(f"Wrote {out_dir}/units.tsv ({len(rows)} rows)")

def write_samples_tsv(out_dir):
    """Write samples.tsv (same for all hybrids)."""
    os.makedirs(out_dir, exist_ok=True)
    sample_row = [
        "HG003", "blood", "research", "male",
        "/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/",
        "true", "false", "gdna", "", "HG003", "1", "1",
        "/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/"
    ]
    with open(os.path.join(out_dir, "samples.tsv"), "w") as f:
        f.write("\t".join(SAMPLES_HEADER) + "\n")
        f.write("\t".join(sample_row) + "\n")
    print(f"Wrote {out_dir}/samples.tsv")

if __name__ == "__main__":
    base = os.path.dirname(os.path.abspath(__file__))
    for ht in ("hiomr", "huomr", "hipmr", "hupmr"):
        out_dir = os.path.join(base, ht)
        write_units_tsv(ht, out_dir)
        write_samples_tsv(out_dir)
    print("\nDone! Generated 4 x 81-row units.tsv + samples.tsv files.")

