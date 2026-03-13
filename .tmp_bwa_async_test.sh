#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
SENTIEON="/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon"
LIC="/fsx/data/cached_envs/Life_Sciences_Manufacturing_Corporation_eval.lic"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"

# Launch bwa test in background on headnode
ssh -i "$KEY" "$HN" "nohup bash -c 'export SENTIEON_LICENSE=$LIC; $SENTIEON bwa mem -R \"@RG\tID:test\tSM:test\" -t 2 -x $BUNDLE/bwa.model $REF /tmp/t100.fq > /tmp/bwa_out.sam 2>/tmp/bwa_err.txt; echo DONE > /tmp/bwa_done.txt' &>/dev/null &"

echo "BWA test launched in background on headnode"
echo "Check results with: ssh -i \$KEY \$HN 'cat /tmp/bwa_done.txt; wc -l /tmp/bwa_out.sam; cat /tmp/bwa_err.txt'"

