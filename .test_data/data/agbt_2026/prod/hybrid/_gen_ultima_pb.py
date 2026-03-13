#!/usr/bin/env python3
"""Generate hybrid Ultima+PacBio units.tsv by combining coverage levels."""

import csv
from pathlib import Path

# Define paths
ug_file = Path(".test_data/data/agbt_2026/prod/ug/units.tsv")
pb_file = Path(".test_data/data/agbt_2026/prod/pb/units.tsv")
output_file = Path(".test_data/data/agbt_2026/prod/hybrid/ultima_pb/units.tsv")

# Ensure output directory exists
output_file.parent.mkdir(parents=True, exist_ok=True)

# Parse Ultima file
ug_data = {}
with open(ug_file) as f:
    reader = csv.DictReader(f, delimiter="\t")
    for row in reader:
        if row["EXPERIMENTID"]:
            cov = row["EXPERIMENTID"]
            ug_data[cov] = row

# Parse PacBio file
pb_data = {}
with open(pb_file) as f:
    reader = csv.DictReader(f, delimiter="\t")
    for row in reader:
        if row["EXPERIMENTID"]:
            cov = row["EXPERIMENTID"]
            pb_data[cov] = row

# Extract coverage levels
ug_covs = sorted([int(k.rstrip("x")) for k in ug_data.keys()])
pb_covs = sorted([int(k.rstrip("x")) for k in pb_data.keys()])

# Generate hybrid matrix
rows = []
lane_id = 0

for ug_cov in ug_covs:
    for pb_cov in pb_covs:
        ug_key = f"{ug_cov}x"
        pb_key = f"{pb_cov}x"
        
        ug_row = ug_data[ug_key]
        pb_row = pb_data[pb_key]
        
        # Create hybrid row
        row = {
            "RUNID": f"HUPa",
            "SAMPLEID": "HG003",
            "EXPERIMENTID": f"SR{ug_cov}x-LR{pb_cov}x",
            "LANEID": str(lane_id),
            "BARCODEID": "D0",
            "LIBPREP": "PF",
            "SEQ_VENDOR": "UG",
            "SEQ_PLATFORM": "ULTIMA",
            "ILMN_R1_PATH": "",
            "ILMN_R2_PATH": "",
            "PACBIO_R1_PATH": "",
            "PACBIO_R2_PATH": "",
            "ONT_R1_PATH": "",
            "ONT_R2_PATH": "",
            "UG_R1_PATH": "",
            "UG_R2_PATH": "",
            "SUBSAMPLE_PCT": "",
            "ILMN_TRIM_READ_LENGTH": "",
            "SAMPLEUSE": "posControl",
            "BWA_KMER": "19",
            "DEEP_MODEL": "WGS",
            "ULTIMA_CRAM": ug_row["ULTIMA_CRAM"],
            "ULTIMA_CRAM_ALIGNER": "ug",
            "ULTIMA_CRAM_SNV_CALLER": "ug",
            "ONT_CRAM": "",
            "ONT_CRAM_ALIGNER": "",
            "ONT_CRAM_SNV_CALLER": "",
            "PB_BAM": pb_row["PB_BAM"],
            "PB_BAM_ALIGNER": "sentmm2",
            "PB_BAM_SNV_CALLER": "sentdpb",
            "ROCHE_BAM": "",
            "ROCHE_BAM_ALIGNER": "",
            "ROCHE_BAM_SNV_CALLER": "",
            "ROCHE_DOWNSAMPLE_RATIO": "",
        }
        rows.append(row)
        lane_id += 1

# Write output
fieldnames = [
    "RUNID", "SAMPLEID", "EXPERIMENTID", "LANEID", "BARCODEID", "LIBPREP",
    "SEQ_VENDOR", "SEQ_PLATFORM", "ILMN_R1_PATH", "ILMN_R2_PATH",
    "PACBIO_R1_PATH", "PACBIO_R2_PATH", "ONT_R1_PATH", "ONT_R2_PATH",
    "UG_R1_PATH", "UG_R2_PATH", "SUBSAMPLE_PCT", "ILMN_TRIM_READ_LENGTH",
    "SAMPLEUSE", "BWA_KMER", "DEEP_MODEL", "ULTIMA_CRAM", "ULTIMA_CRAM_ALIGNER",
    "ULTIMA_CRAM_SNV_CALLER", "ONT_CRAM", "ONT_CRAM_ALIGNER", "ONT_CRAM_SNV_CALLER",
    "PB_BAM", "PB_BAM_ALIGNER", "PB_BAM_SNV_CALLER", "ROCHE_BAM",
    "ROCHE_BAM_ALIGNER", "ROCHE_BAM_SNV_CALLER", "ROCHE_DOWNSAMPLE_RATIO",
]

with open(output_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} rows in {output_file}")
print(f"Coverage matrix: {len(ug_covs)} Ultima × {len(pb_covs)} PacBio = {len(rows)} total")

