#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

ssh -i "$KEY" "$HN" "which sentieon 2>/dev/null || find /fsx -maxdepth 5 -name 'sentieon' -type f 2>/dev/null | head -3"

