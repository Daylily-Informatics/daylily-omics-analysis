#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
scp -i "$PEM" .tmp_remote_check_cli_vcf.sh "$HOST":/tmp/check_cli_vcf.sh
ssh -i "$PEM" "$HOST" 'bash /tmp/check_cli_vcf.sh'

