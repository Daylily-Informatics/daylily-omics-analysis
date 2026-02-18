#!/bin/bash
set -euo pipefail
KEY=~/.ssh/lsmc-omics-us-west-2.pem
HOST=ubuntu@44.231.76.175
SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30 $HOST"

$SSH 'ps aux | grep snakemake | grep -v grep | wc -l; echo SEP1; squeue -u ubuntu 2>/dev/null | wc -l; echo SEP2; for s in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x t3-hybrid-mod-ug-ont-3x; do echo "SESS:$s"; tmux capture-pane -t $s -p 2>/dev/null | grep -E "SUCCESS|FAIL|Error|steps.*done|Submitted|Womp" | tail -3; done'

