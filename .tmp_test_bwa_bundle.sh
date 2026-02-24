#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"
REF="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
R1="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"

echo "=== Slurm .err: look for bwa errors (not script text) ==="
ssh -i "$KEY" "$HN" "awk '/^Shutting down|exit code|^Error|^error|^WARNING|^Fail|bash: |cannot open|No such file/{ print NR\": \"\$0 }' \$(ls -t $STD_DIR/logs/slurm/sentdhiom_sr_align/*.err 2>/dev/null | head -1) 2>/dev/null | tail -20"

echo ""
echo "=== Quick bwa test: 100 reads with bundle model ==="
ssh -i "$KEY" "$HN" "cd $STD_DIR && source ~/.bashrc && conda activate DAYOA && igzip -cd $R1 | head -400 > /tmp/test100.fq && sentieon bwa mem -R '@RG\tID:test\tSM:test' -t 4 -x $BUNDLE/bwa.model $REF /tmp/test100.fq 2>/tmp/bwa_test.err | head -20 && echo '--- stderr ---' && cat /tmp/bwa_test.err"

echo ""
echo "=== Quick bwa test WITHOUT model ==="
ssh -i "$KEY" "$HN" "cd $STD_DIR && source ~/.bashrc && conda activate DAYOA && sentieon bwa mem -R '@RG\tID:test\tSM:test' -t 4 $REF /tmp/test100.fq 2>/tmp/bwa_test2.err | head -20 && echo '--- stderr ---' && cat /tmp/bwa_test2.err"

