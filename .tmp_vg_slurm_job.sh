#!/bin/bash
#SBATCH --job-name=vg_pangenome_stage
#SBATCH --comment=RnD
#SBATCH --partition=i192mem,i192bigmem
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/fsx/scratch/pangenome/vg_stage_%j.out
#SBATCH --error=/fsx/scratch/pangenome/vg_stage_%j.err

set -euo pipefail

STAGING=/fsx/scratch/pangenome
GBZ="$STAGING/hprc-v2.0-mc-grch38.gbz"

# Initialize conda
eval "$(/home/ubuntu/miniconda3/bin/conda 'shell.bash' 'hook' 2>/dev/null)"
conda activate vg_tools

echo "$(date) - Starting on $(hostname)"
echo "vg version: $(vg version 2>&1 | head -1)"
echo "Memory: $(free -h | grep Mem)"

# Clean up 0-byte artifact from failed headnode run
rm -f "$STAGING/hprc-v2.0-mc-grch38.xg"

echo "$(date) - Step 1: Generate .xg from .gbz"
vg convert -x "$GBZ" > "$STAGING/hprc-v2.0-mc-grch38.xg"
echo "$(date) - .xg done ($(ls -lh $STAGING/hprc-v2.0-mc-grch38.xg | awk '{print $5}'))"

echo "$(date) - Step 2: Generate .snarls from .gbz"
vg snarls -T "$GBZ" > "$STAGING/hprc-v2.0-mc-grch38.snarls"
echo "$(date) - .snarls done ($(ls -lh $STAGING/hprc-v2.0-mc-grch38.snarls | awk '{print $5}'))"

echo "$(date) - Final listing:"
ls -lh "$STAGING/"
echo "$(date) - ALL DONE"

