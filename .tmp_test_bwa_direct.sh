#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
R1="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"
SENTIEON="/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon"

echo "=== Check sentieon binary ==="
ssh -i "$KEY" "$HN" "ls -la $SENTIEON 2>/dev/null || echo 'NOT FOUND'"

echo ""
echo "=== Find sentieon binary ==="
ssh -i "$KEY" "$HN" "find /fsx/data/cached_envs/sentieon-genomics-202503.02 -name 'sentieon' -type f 2>/dev/null | head -5"
ssh -i "$KEY" "$HN" "find /fsx/resources/environments/conda -name 'sentieon' -type f 2>/dev/null | head -5"

echo ""
echo "=== License file ==="
ssh -i "$KEY" "$HN" "ls -la /fsx/data/cached_envs/sentieon-genomics-202503.02/sentieon*.lic 2>/dev/null || echo 'no lic file'"
ssh -i "$KEY" "$HN" "echo \$SENTIEON_LICENSE 2>/dev/null || echo 'not set'"

echo ""
echo "=== Extract 100 reads for test ==="
ssh -i "$KEY" "$HN" "igzip -cd $R1 2>/dev/null | head -400 > /tmp/test100.fq && wc -l /tmp/test100.fq"

