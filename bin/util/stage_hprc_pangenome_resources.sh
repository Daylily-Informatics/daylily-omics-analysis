#!/usr/bin/env bash
set -euo pipefail

# Stage HPRC pangenome resources (GBZ + HAPL) and derive XG + SNARLS.
#
# Usage:
#   ./stage_hprc_pangenome_resources.sh /absolute/path/to/pangenome_dir
#
# Requirements:
#   - aws CLI (for v2.0 option) OR curl (for v1.1 option)
#   - vg in PATH (for vg convert + vg snarls)

OUTDIR="${1:-}"
if [[ -z "${OUTDIR}" ]]; then
  echo "ERROR: provide output directory" >&2
  exit 1
fi
mkdir -p "${OUTDIR}"
cd "${OUTDIR}"

echo "Output dir: ${OUTDIR}"

# -----------------------------
# Option A: HPRC v2.0 (release2 scratch path)
# -----------------------------
# Confirm file list, then copy gbz/hapl.
echo ""
echo "Option A (recommended): HPRC v2.0 via aws s3 (no-sign-request)"
echo "Listing:"
aws s3 ls s3://human-pangenomics/pangenomes/scratch/2025_02_28_minigraph_cactus/hprc-v2.0-mc-grch38/ --no-sign-request

echo ""
echo "Downloading GBZ + HAPL:"
aws s3 cp --no-sign-request \
  s3://human-pangenomics/pangenomes/scratch/2025_02_28_minigraph_cactus/hprc-v2.0-mc-grch38/hprc-v2.0-mc-grch38.gbz \
  ./hprc-v2.0-mc-grch38.gbz

aws s3 cp --no-sign-request \
  s3://human-pangenomics/pangenomes/scratch/2025_02_28_minigraph_cactus/hprc-v2.0-mc-grch38/hprc-v2.0-mc-grch38.hapl \
  ./hprc-v2.0-mc-grch38.hapl

echo ""
echo "Deriving XG + SNARLS:"
vg convert -x ./hprc-v2.0-mc-grch38.gbz > ./hprc-v2.0-mc-grch38.xg
vg snarls -T ./hprc-v2.0-mc-grch38.gbz > ./hprc-v2.0-mc-grch38.snarls

echo ""
echo "Done. Files staged:"
ls -lh ./hprc-v2.0-mc-grch38.gbz ./hprc-v2.0-mc-grch38.hapl ./hprc-v2.0-mc-grch38.xg ./hprc-v2.0-mc-grch38.snarls

# -----------------------------
# Option B: HPRC v1.1 (freeze1) via https
# -----------------------------
# Uncomment if you want the older freeze1 bundle instead.
#
# curl -L -O \
#   https://human-pangenomics.s3.us-west-2.amazonaws.com/pangenomes/freeze/freeze1/minigraph-cactus/hprc-v1.1-mc-grch38/hprc-v1.1-mc-grch38.gbz
# curl -L -O \
#   https://human-pangenomics.s3.us-west-2.amazonaws.com/pangenomes/freeze/freeze1/minigraph-cactus/hprc-v1.1-mc-grch38/hprc-v1.1-mc-grch38.hapl
# vg convert -x hprc-v1.1-mc-grch38.gbz > hprc-v1.1-mc-grch38.xg
# vg snarls -T hprc-v1.1-mc-grch38.gbz > hprc-v1.1-mc-grch38.snarls
