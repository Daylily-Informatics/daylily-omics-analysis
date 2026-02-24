#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
SENTIEON="/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon"
LIC="/fsx/data/cached_envs/Life_Sciences_Manufacturing_Corporation_eval.lic"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"

echo "=== BWA model exists? ==="
ssh -i "$KEY" "$HN" "test -e ${BUNDLE}/bwa.model && echo EXISTS || echo NOT FOUND"

echo ""
echo "=== Test bwa with bundle/bwa.model ==="
ssh -i "$KEY" "$HN" "export SENTIEON_LICENSE=$LIC; $SENTIEON bwa mem -R '@RG\tID:test\tSM:test' -t 2 -x $BUNDLE/bwa.model $REF /tmp/t100.fq 2>/tmp/bwa_e.txt | head -3; echo EXIT_CODE=\$?; echo '--- stderr ---'; cat /tmp/bwa_e.txt"

