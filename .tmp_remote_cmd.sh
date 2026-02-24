#!/bin/bash
# Reusable remote command runner — no heredoc
# Usage: bash .tmp_remote_cmd.sh <remote_command>
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
ssh -i "$PEM" "$HOST" "$1"

