#!/bin/bash
set -euo pipefail

# Get samtools and bwa into PATH
CONDA_ENV="/fsx/resources/environments/conda/ubuntu/ip-10-0-0-21/373e62c5ce20a4c69d98bd39b2804758_"
export PATH="${CONDA_ENV}/bin:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin:$PATH"

echo "samtools: $(which samtools 2>&1)"
echo "bwa: $(which bwa 2>&1)"

BASE_URL="https://storage.googleapis.com/broad-references/hg38/v0/chrM"

FILES=(
  "Homo_sapiens_assembly38.chrM.fasta"
  "Homo_sapiens_assembly38.chrM.fasta.fai"
  "Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta"
  "Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta.fai"
  "ShiftBack.chain"
  "blacklist_sites.hg38.chrM.bed"
)

for DIR in /fsx/scratch/hg38/chrM /fsx/scratch/hg38_broad/chrM; do
  echo "=== Setting up $DIR ==="
  mkdir -p "$DIR"
  cd "$DIR"

  for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
      echo "  Downloading $f ..."
      curl -sS -O "${BASE_URL}/${f}"
    else
      echo "  Already exists: $f"
    fi
  done

  # Generate .dict files if missing
  for fa in *.fasta; do
    dict="${fa%.fasta}.dict"
    if [ ! -f "$dict" ]; then
      echo "  Creating dict for $fa ..."
      samtools dict "$fa" > "$dict"
    fi
  done

  # BWA index both FASTAs
  for fa in *.fasta; do
    if [ ! -f "${fa}.bwt" ]; then
      echo "  BWA indexing $fa ..."
      bwa index "$fa"
    else
      echo "  BWA index exists for $fa"
    fi
  done

  echo "  Done: $DIR"
  ls -lh "$DIR"
  echo ""
done

echo "=== All chrM references ready ==="

