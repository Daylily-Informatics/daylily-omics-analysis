#!/usr/bin/env bash
# scp remote script to headnode and run it
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

scp -i "$KEY" "$SCRIPT_DIR/.tmp_remote_status.sh" "$HN:/tmp/forge_remote_status.sh"
ssh -i "$KEY" "$HN" "bash /tmp/forge_remote_status.sh"

