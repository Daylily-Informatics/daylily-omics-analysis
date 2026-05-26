#!/bin/bash
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate DAYOA
export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

HYBRID_SELECT=$(python -c "from importlib_resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_select.py'))")
echo "HYBRID_SELECT script: $HYBRID_SELECT"
echo ""
echo "=== Usage ==="
sentieon pyexec "$HYBRID_SELECT" --help 2>&1

