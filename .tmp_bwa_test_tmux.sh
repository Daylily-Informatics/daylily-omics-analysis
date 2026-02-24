#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
R1="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"

echo "=== Find license file ==="
ssh -i "$KEY" "$HN" "find /fsx -maxdepth 4 -name '*.lic' 2>/dev/null | head -5"

echo ""
echo "=== Check SENTIEON_LICENSE in the conda env ==="
ssh -i "$KEY" "$HN" "grep -r SENTIEON_LICENSE $STD_DIR/config/ 2>/dev/null | head -5"
ssh -i "$KEY" "$HN" "grep -r SENTIEON_LICENSE /fsx/resources/environments/conda/ubuntu/ip-10-0-0-214/9753824a848ed13f70a3d5e42e354650_/etc/conda/activate.d/ 2>/dev/null | head -5 || echo 'no activate.d'"

echo ""
echo "=== Send test command to STD tmux (it has the full env) ==="
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_std_chr21 'igzip -cd $R1 | head -400 > /tmp/test100.fq && sentieon bwa mem -R \"@RG\tID:test\tSM:test\" -t 2 -x $BUNDLE/bwa.model $REF /tmp/test100.fq 2>/tmp/bwa_err.txt | head -5 > /tmp/bwa_out.txt && echo DONE' Enter"
sleep 5
ssh -i "$KEY" "$HN" "echo '=== stdout ===' && cat /tmp/bwa_out.txt 2>/dev/null && echo '=== stderr ===' && cat /tmp/bwa_err.txt 2>/dev/null"

