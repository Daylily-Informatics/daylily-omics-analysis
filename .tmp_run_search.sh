#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
scp -i "$PEM" .tmp_remote_find_cli.sh "$HOST":/tmp/find_cli.sh
ssh -i "$PEM" "$HOST" 'bash /tmp/find_cli.sh'

