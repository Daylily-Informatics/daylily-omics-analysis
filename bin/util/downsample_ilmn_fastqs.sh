#!/bin/bash
set -euo pipefail

INPUT_DIR="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007"
OUT_DIR="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007_downsampled"
THREADS=16
SEED=7

mkdir -p "$OUT_DIR"

# Coverage fractions for 5x, 10x, 15x, 20x from 30x input
#declare -A DOWNSAMPLE_MAP=( ["5x"]=0.1667 ["10x"]=0.3333 ["15x"]=0.5 ["20x"]=0.6667 )
declare -A DOWNSAMPLE_MAP=( ["3x"]=0.1 ["1.5x"]=0.05 ["1x"]=0.0333333333 ["0.4x"]=0.0133333333 ["0.1x"]=0.0033333333 )

# Sample loop
for fq1 in "$INPUT_DIR"/*_30x_R1.fastq.gz; do
    fq2="${fq1/_R1/_R2}"
    sample=$(basename "$fq1" | cut -d'_' -f1)

    for tgt_cov in "${!DOWNSAMPLE_MAP[@]}"; do
        pct="${DOWNSAMPLE_MAP[$tgt_cov]}"
        out_prefix="${OUT_DIR}/${sample}_${tgt_cov}"

        echo "Downsampling $sample to $tgt_cov (fraction: $pct)..."

        (
        seqkit sample -j $THREADS --line-width=0 --quiet --rand-seed=$SEED --seq-type=dna \
            --proportion=$pct "$fq1" > "${out_prefix}_R1.fastq"

        seqkit sample -j $THREADS --line-width=0 --quiet --rand-seed=$SEED --seq-type=dna \
            --proportion=$pct "$fq2" > "${out_prefix}_R2.fastq"

        pigz -p $THREADS "${out_prefix}_R1.fastq"
        pigz -p $THREADS "${out_prefix}_R2.fastq"
        ) &
    done
done

wait
echo "All downsampling complete."
