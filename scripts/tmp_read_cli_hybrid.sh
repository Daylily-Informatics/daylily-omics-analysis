#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== sentieon_cli/dnascope_hybrid.py (version 1.5.2) ==="
$SSH $HN 'cat /fsx/data/cached_envs/sentieon_cli-1.5.2/sentieon_cli/dnascope_hybrid.py'

