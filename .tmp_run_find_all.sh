#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
scp -i "$PEM" .tmp_remote_find_all_vcfs.sh "$HOST":/tmp/find_all_vcfs.sh
ssh -i "$PEM" "$HOST" 'bash /tmp/find_all_vcfs.sh'

