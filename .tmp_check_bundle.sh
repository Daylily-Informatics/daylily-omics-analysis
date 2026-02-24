#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== Bundle directory contents ==="
ssh -i "$KEY" "$HN" "ls -la /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle/"

echo ""
echo "=== All model files in bundle ==="
ssh -i "$KEY" "$HN" "find /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle/ -name '*.model' -o -name '*.model.*'"

echo ""
echo "=== Check slurm .err for bwa stderr (STD) ==="
ssh -i "$KEY" "$HN" "grep -i 'error\|fail\|warn\|cannot\|bwa' /fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis/logs/slurm/sentdhiom_sr_align/*.err 2>/dev/null | grep -v 'set -euo\|echo\|if \[' | tail -20"

