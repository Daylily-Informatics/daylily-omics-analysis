#!/bin/bash
set -euo pipefail
# Check headnode is reachable and get cluster info
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@44.231.76.175 \
  "hostname && uptime && echo '---' && ls /fsx/analysis_results/ubuntu/ | head -20 && echo '---TMUX---' && tmux ls 2>&1 || true"

