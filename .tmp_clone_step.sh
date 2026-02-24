#!/bin/bash
set -euo pipefail
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@44.231.76.175 \
  "source ~/.bashrc && day-clone -t feat/modular-hybrid-workflows -w ssh -d hiomr_xfer_shard_chr21_20260221 2>&1 | tail -10"

