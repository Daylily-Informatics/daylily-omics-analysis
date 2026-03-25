#!/bin/bash
set -euo pipefail

CONDA_ENV="/fsx/resources/environments/conda/ubuntu/ip-10-0-0-21/373e62c5ce20a4c69d98bd39b2804758_"
export PATH="${CONDA_ENV}/bin:$PATH"

SHIFT=8000

for DIR in /fsx/scratch/hg38/chrM /fsx/scratch/hg38_broad/chrM; do
  echo "=== Fixing $DIR ==="
  cd "$DIR"

  MT_FA="Homo_sapiens_assembly38.chrM.fasta"
  MT_LEN=$(grep -v '^>' "$MT_FA" | tr -d '\n' | wc -c)
  TAIL_LEN=$((MT_LEN - SHIFT))
  echo "  MT length: $MT_LEN, shift: $SHIFT, tail: $TAIL_LEN"

  # Overwrite ShiftBack.chain
  cat > ShiftBack.chain <<EOF
chain 1000000 chrM $MT_LEN + $SHIFT $MT_LEN chrM $MT_LEN + 0 $TAIL_LEN 1
$TAIL_LEN

chain 1000000 chrM $MT_LEN + 0 $SHIFT chrM $MT_LEN + $TAIL_LEN $MT_LEN 2
$SHIFT

EOF
  echo "  ShiftBack.chain: $(wc -c < ShiftBack.chain) bytes"
  cat ShiftBack.chain

  # Overwrite blacklist BED
  cat > blacklist_sites.hg38.chrM.bed <<EOF
chrM	300	302
chrM	3106	3107
chrM	16181	16183
EOF
  echo "  blacklist: $(wc -c < blacklist_sites.hg38.chrM.bed) bytes"
  cat blacklist_sites.hg38.chrM.bed
  echo ""
done

echo "=== Done ==="

