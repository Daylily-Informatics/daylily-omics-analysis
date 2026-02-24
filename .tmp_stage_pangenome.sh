#!/bin/bash
set -euo pipefail

# Initialize conda
eval "$(/home/ubuntu/miniconda3/bin/conda 'shell.bash' 'hook' 2>/dev/null)"

STAGING=/fsx/scratch/pangenome
GBZ_SRC=/fsx/data/genomic_data/organism_references/H_sapiens/panhg38/hprc-v2.0-mc-grch38.gbz
HAPL_SRC=/fsx/data/genomic_data/organism_references/H_sapiens/panhg38/hprc-v2.0-mc-grch38.hapl
BUNDLE_SRC=/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeWGS1.0.bundle/SentieonIlluminaPangenomeWGS1.0.bundle

mkdir -p "$STAGING"
cd "$STAGING"

echo "=== Step 1: Create conda env with vg ==="
if conda env list | grep -q vg_tools; then
    echo "vg_tools env already exists, activating..."
else
    echo "Creating vg_tools env..."
    conda create -y -n vg_tools -c conda-forge -c bioconda vg 2>&1 | tail -5
fi
conda activate vg_tools
echo "vg version: $(vg version 2>&1 | head -1)"

echo "=== Step 2: Symlink source files ==="
if [ ! -e "$STAGING/hprc-v2.0-mc-grch38.gbz" ]; then
    ln -s "$GBZ_SRC" "$STAGING/hprc-v2.0-mc-grch38.gbz"
    echo "Symlinked .gbz"
else
    echo ".gbz already present"
fi

if [ ! -e "$STAGING/hprc-v2.0-mc-grch38.hapl" ]; then
    ln -s "$HAPL_SRC" "$STAGING/hprc-v2.0-mc-grch38.hapl"
    echo "Symlinked .hapl"
else
    echo ".hapl already present"
fi

echo "=== Step 3: Stage model bundle ==="
if [ ! -e "$STAGING/SentieonIlluminaPangenomeWGS1.0.bundle" ]; then
    cp "$BUNDLE_SRC" "$STAGING/SentieonIlluminaPangenomeWGS1.0.bundle"
    echo "Copied model bundle"
else
    echo "Model bundle already present"
fi

echo "=== Step 4: Generate .xg from .gbz ==="
if [ ! -e "$STAGING/hprc-v2.0-mc-grch38.xg" ]; then
    echo "Running vg convert -x (this may take a while)..."
    vg convert -x "$STAGING/hprc-v2.0-mc-grch38.gbz" > "$STAGING/hprc-v2.0-mc-grch38.xg"
    echo "Generated .xg ($(ls -lh $STAGING/hprc-v2.0-mc-grch38.xg | awk '{print $5}'))"
else
    echo ".xg already present ($(ls -lh $STAGING/hprc-v2.0-mc-grch38.xg | awk '{print $5}'))"
fi

echo "=== Step 5: Generate .snarls from .gbz ==="
if [ ! -e "$STAGING/hprc-v2.0-mc-grch38.snarls" ]; then
    echo "Running vg snarls -T (this may take a while)..."
    vg snarls -T "$STAGING/hprc-v2.0-mc-grch38.gbz" > "$STAGING/hprc-v2.0-mc-grch38.snarls"
    echo "Generated .snarls ($(ls -lh $STAGING/hprc-v2.0-mc-grch38.snarls | awk '{print $5}'))"
else
    echo ".snarls already present ($(ls -lh $STAGING/hprc-v2.0-mc-grch38.snarls | awk '{print $5}'))"
fi

echo "=== Final listing ==="
ls -lh "$STAGING/"
echo "=== ALL DONE ==="

