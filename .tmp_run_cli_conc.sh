#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
scp -i "$PEM" .tmp_remote_get_cli_conc.sh "$HOST":/tmp/get_cli_conc.sh
ssh -i "$PEM" "$HOST" 'bash /tmp/get_cli_conc.sh'

