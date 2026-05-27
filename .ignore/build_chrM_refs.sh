#!/bin/bash
set -euo pipefail

CONDA_ENV="/fsx/resources/environments/conda/ubuntu/ip-10-0-0-21/373e62c5ce20a4c69d98bd39b2804758_"
export PATH="${CONDA_ENV}/bin:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin:$PATH"

FULL_REF="/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta"
SHIFT=8000

for DIR in /fsx/scratch/hg38/chrM /fsx/scratch/hg38_broad/chrM; do
  echo "=== Building chrM refs in $DIR ==="
  rm -f "$DIR"/*.fasta* "$DIR"/*.dict  # clean up the bad XML files
  mkdir -p "$DIR"
  cd "$DIR"

  MT_FA="Homo_sapiens_assembly38.chrM.fasta"
  MT_SHIFTED="Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta"

  # --- Step 1: Extract chrM from full reference ---
  if [ ! -f "$MT_FA" ] || [ "$(wc -c < "$MT_FA")" -lt 1000 ]; then
    echo "  Extracting chrM from $FULL_REF ..."
    samtools faidx "$FULL_REF" chrM > "$MT_FA"
    echo "  Size: $(wc -c < "$MT_FA") bytes"
  fi

  # --- Step 2: Create shifted version (shift by 8000 bases) ---
  if [ ! -f "$MT_SHIFTED" ] || [ "$(wc -c < "$MT_SHIFTED")" -lt 1000 ]; then
    echo "  Creating shifted MT reference (shift=$SHIFT) ..."
    python3 -c "
import sys
with open('$MT_FA') as f:
    lines = f.readlines()
header = lines[0].strip()
seq = ''.join(l.strip() for l in lines[1:])
shifted = seq[$SHIFT:] + seq[:$SHIFT]
# Write with 70-char lines
print('>chrM', file=sys.stdout)
for i in range(0, len(shifted), 70):
    print(shifted[i:i+70], file=sys.stdout)
" > "$MT_SHIFTED"
    echo "  Size: $(wc -c < "$MT_SHIFTED") bytes"
  fi

  # --- Step 3: Create ShiftBack.chain ---
  if [ ! -f "ShiftBack.chain" ] || [ "$(wc -c < "ShiftBack.chain")" -lt 50 ]; then
    echo "  Creating ShiftBack.chain ..."
    MT_LEN=$(grep -v '^>' "$MT_FA" | tr -d '\n' | wc -c)
    TAIL_LEN=$((MT_LEN - SHIFT))
    cat > ShiftBack.chain <<EOF
chain 1000000 chrM $MT_LEN + $SHIFT $MT_LEN chrM $MT_LEN + 0 $TAIL_LEN 1
$TAIL_LEN

chain 1000000 chrM $MT_LEN + 0 $SHIFT chrM $MT_LEN + $TAIL_LEN $MT_LEN 2
$SHIFT

EOF
    echo "  ShiftBack.chain created"
  fi

  # --- Step 4: Create blacklist BED (NuMT regions) ---
  if [ ! -f "blacklist_sites.hg38.chrM.bed" ] || [ "$(wc -c < "blacklist_sites.hg38.chrM.bed")" -lt 10 ]; then
    echo "  Creating blacklist_sites.hg38.chrM.bed ..."
    # Standard GATK MT blacklist: site 301 and 302 (0-based), plus 3107 (N insertion)
    cat > blacklist_sites.hg38.chrM.bed <<EOF
chrM	300	302
chrM	3106	3107
chrM	16181	16183
EOF
    echo "  Blacklist BED created"
  fi

  # --- Step 5: Index everything ---
  for fa in "$MT_FA" "$MT_SHIFTED"; do
    echo "  Indexing $fa ..."
    samtools faidx "$fa"
    samtools dict "$fa" > "${fa%.fasta}.dict"
    bwa index "$fa"
  done

  echo "  Done: $DIR"
  ls -lh "$DIR"
  echo ""
done

echo "=== All chrM references built and indexed ==="

