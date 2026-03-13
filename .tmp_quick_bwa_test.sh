#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
SENTIEON="/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
R1="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"
LIC=$(ssh -i "$KEY" "$HN" "find /fsx -maxdepth 3 -name 'sentieon*.lic' 2>/dev/null | head -1")

echo "=== License: $LIC ==="

echo ""
echo "=== Test bwa mem with bundle model (100 reads) ==="
ssh -i "$KEY" "$HN" "export SENTIEON_LICENSE=$LIC; igzip -cd $R1 | head -400 > /tmp/test100.fq; $SENTIEON bwa mem -R '@RG\tID:test\tSM:test' -t 2 -x $BUNDLE/bwa.model $REF /tmp/test100.fq 2>/tmp/bwa_stderr.txt | wc -l; echo '--- stderr ---'; cat /tmp/bwa_stderr.txt"

