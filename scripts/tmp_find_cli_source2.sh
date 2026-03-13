#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== Find sentieon_cli Python files ==="
$SSH $HN 'find /fsx/data/cached_envs/ -path "*/sentieon_cli/*dnascope*" -name "*.py" 2>/dev/null | head -20'

echo ""
echo "=== Find sentieon_cli via conda envs ==="
$SSH $HN 'find /home/ubuntu/mambaforge/envs/ -path "*/sentieon_cli/*" -name "*.py" 2>/dev/null | head -30'

echo ""
echo "=== Find via snakemake conda envs ==="  
$SSH $HN 'find /fsx/analysis_results/ -maxdepth 10 -path "*/.snakemake/conda/*/lib/python*/site-packages/sentieon_cli/*" -name "*.py" 2>/dev/null | head -30'

echo ""
echo "=== Find any sentieon_cli directory ==="
$SSH $HN 'find / -maxdepth 8 -type d -name "sentieon_cli" 2>/dev/null | head -10'

