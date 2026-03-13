#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== Bundle file type ==="
ssh -i "$KEY" "$HN" "file /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"

echo ""
echo "=== Bundle file size ==="
ssh -i "$KEY" "$HN" "ls -lh /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaONT2.0.bundle"

echo ""
echo "=== All bundles in dir ==="
ssh -i "$KEY" "$HN" "ls -la /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/"

echo ""
echo "=== Look for bwa.model anywhere under bundles ==="
ssh -i "$KEY" "$HN" "find /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/ -name '*bwa*' -o -name '*model*' 2>/dev/null"

echo ""
echo "=== Check if bundle has been extracted somewhere ==="
ssh -i "$KEY" "$HN" "find /fsx/data/cached_envs/sentieon-genomics-202503.02/ -name 'bwa.model' 2>/dev/null | head -5"

echo ""
echo "=== Check sentieon CLI docs: how the bundle is used ==="
ssh -i "$KEY" "$HN" "sentieon bwa mem --help 2>&1 | grep -i 'model\|bundle' | head -10 || echo 'no help output'"

