#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
BUNDLE="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"

echo "=== List ar archive contents ==="
ssh -i "$KEY" "$HN" "ar t $BUNDLE 2>/dev/null || echo 'ar t failed'"

echo ""
echo "=== Quick test: can sentieon bwa mem read the model from bundle? ==="
ssh -i "$KEY" "$HN" "source ~/.bashrc && sentieon bwa mem -x $BUNDLE/bwa.model 2>&1 | head -5 || echo 'exit code: \$?'"

echo ""
echo "=== Try the direct bundle path (not subpath) ==="
ssh -i "$KEY" "$HN" "source ~/.bashrc && sentieon bwa mem -x $BUNDLE 2>&1 | head -5 || echo 'exit code: \$?'"

echo ""
echo "=== Check how 1.1 bundle is structured (it also exists) ==="
ssh -i "$KEY" "$HN" "file /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT1.1.bundle"
ssh -i "$KEY" "$HN" "ar t /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT1.1.bundle 2>/dev/null | head -10"

echo ""
echo "=== Check extracted directories (some bundles are dirs) ==="
ssh -i "$KEY" "$HN" "ls /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/DNAscopeONT2.2.bundle/ 2>/dev/null | head -10"

