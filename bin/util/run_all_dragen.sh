#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# ------- Config -------
# Set SAMPLE_FILTER to "HG002" (literal) to run only HG002,
# or leave default "HG00[1-7]" to run HG001–HG007
SAMPLE_FILTER="${SAMPLE_FILTER:-HG00[1-7]}"
COV_FILTER="${COV_FILTER:-*x}"   # e.g. "30x" or "*x"

TRUTH_BASE="/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1"

# Build the glob (no brace expansion; use [] or literals)
VCF_GLOB="$HOME/dragen_results/mega/results_all/${SAMPLE_FILTER}_*/${SAMPLE_FILTER}_${COV_FILTER}.hard-filtered.vcf.gz"

# Materialize matches so we can check empties
mapfile -t VCFs < <(compgen -G "$VCF_GLOB")

if (( ${#VCFs[@]} == 0 )); then
  echo "ERROR: No VCFs matched: $VCF_GLOB" >&2
  exit 1
fi

for vcf in "${VCFs[@]}"; do
  file="$(basename "$vcf")"

  # Expect: HG00N_XXx.hard-filtered.vcf.gz
  if [[ "$file" =~ ^(HG00[1-7])_([0-9]+x)\.hard-filtered\.vcf\.gz$ ]]; then
    HG_UID="${BASH_REMATCH[1]}"
    COVERAGE="${BASH_REMATCH[2]}"
  else
    echo "WARNING: could not parse HG/COVERAGE from $file" >&2
    continue
  fi

  truth_dir_base="${TRUTH_BASE}/${HG_UID}"
  if [[ ! -d "$truth_dir_base" ]]; then
    echo "WARNING: No truth dir for $HG_UID at $truth_dir_base" >&2
    continue
  fi

  for subdir in hg38 giabHC giabHC_x_ultima; do
    truth_dir="${truth_dir_base}/${subdir}"
    if [[ ! -d "$truth_dir" ]]; then
      echo "WARNING: Missing subdir $truth_dir" >&2
      continue
    fi

    outdir="$PWD/mega_concordance/${HG_UID}_${COVERAGE}_${subdir}/"
    mkdir -p "$outdir"

    echo "Running: $HG_UID $COVERAGE vs $subdir"
    bash bin/run_concordance_standalone.sh "$vcf" "$truth_dir" "$outdir" "$HG_UID"
  done
done
