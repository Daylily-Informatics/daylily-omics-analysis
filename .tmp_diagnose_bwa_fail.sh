#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== Full STD sr_align log ==="
ssh -i "$KEY" "$HN" "cat $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/log/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.21.sr_align.log 2>/dev/null"

echo ""
echo "=== Check FASTQ symlinks ==="
ssh -i "$KEY" "$HN" "ls -la $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.R1.fastq.gz 2>/dev/null"
ssh -i "$KEY" "$HN" "ls -la $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.R2.fastq.gz 2>/dev/null"

echo ""
echo "=== FASTQ file sizes ==="
ssh -i "$KEY" "$HN" "readlink -f $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.R1.fastq.gz | xargs ls -lh"
ssh -i "$KEY" "$HN" "readlink -f $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.R2.fastq.gz | xargs ls -lh"

echo ""
echo "=== Quick FASTQ read check (first 4 lines = 1 read) ==="
ssh -i "$KEY" "$HN" "igzip -cd /fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz 2>/dev/null | head -8"

echo ""
echo "=== BWA model exists? ==="
ssh -i "$KEY" "$HN" "ls -la /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle/bwa.model 2>/dev/null || echo 'NOT FOUND'"

echo ""
echo "=== Reference index exists? ==="
ssh -i "$KEY" "$HN" "ls -la /fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta.bwt* 2>/dev/null | head -5"

