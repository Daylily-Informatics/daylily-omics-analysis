#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
scp -i "$PEM" .tmp_remote_check_cmr.sh "$HOST":/tmp/check_cmr.sh
ssh -i "$PEM" "$HOST" 'bash /tmp/check_cmr.sh'

