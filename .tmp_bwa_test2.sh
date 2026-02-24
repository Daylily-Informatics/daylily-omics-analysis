#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
R1="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"

# Find license
ssh -i "$KEY" "$HN" "find /fsx -maxdepth 4 -name '*.lic' 2>/dev/null | head -3"

