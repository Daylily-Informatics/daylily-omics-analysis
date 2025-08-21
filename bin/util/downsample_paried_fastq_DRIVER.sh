#!/usr/bin/env bash
set -euo pipefail

# Source directory with your 30x pairs
BASEDIR="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007"
OUTROOT="${BASEDIR}/downsampled"
SEED=42

# Desired coverages and corresponding fractions from 30x
# 3x=0.1, 1.5x=0.05, 1x≈0.0333333333, 0.4x≈0.0133333333, 0.1x≈0.0033333333
declare -A FRAC=(
  ["3x"]="0.1"
  ["1.5x"]="0.05"
  ["1x"]="0.0333333333"
  ["0.4x"]="0.0133333333"
  ["0.1x"]="0.0033333333"
)

mkdir -p "${OUTROOT}"

for r1 in "${BASEDIR}"/HG*_30x_R1.fastq.gz; do
  sample="$(basename "${r1}" | cut -d_ -f1)"
  r2="${BASEDIR}/${sample}_30x_R2.fastq.gz"
  if [[ ! -f "${r2}" ]]; then
    echo "Missing R2 for ${sample}" >&2
    exit 1
  fi

  for cov in 3x 1.5x 1x 0.4x 0.1x; do
    frac="${FRAC[$cov]}"
    outdir="${OUTROOT}/${sample}/${cov}"
    mkdir -p "${outdir}"
    o1="${outdir}/${sample}_${cov}_R1.fastq.gz"
    o2="${outdir}/${sample}_${cov}_R2.fastq.gz"

    echo "[$(date)] ${sample} -> ${cov} (fraction=${frac})"
    ./downsample_paired_fastq.py \
      -1 "${r1}" -2 "${r2}" \
      -f "${frac}" -s "${SEED}" \
      -o1 "${o1}" -o2 "${o2}"
  done
done

echo "Done. Outputs under: ${OUTROOT}"
