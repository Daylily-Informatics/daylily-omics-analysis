#!/bin/bash
set -euo pipefail
SSH="ssh -i $HOME/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=60 ubuntu@44.231.76.175"

echo "=== Collecting HG004-7 job IDs ==="
JOB_IDS=$($SSH "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu -o '%.10i %.80j' 2>&1 | grep -E 'HG00[4-7]' | awk '{print \$1}' | tr '\n' ',' | sed 's/,$//'")

echo "Job IDs to cancel: $JOB_IDS"
COUNT=$(echo "$JOB_IDS" | tr ',' '\n' | wc -l | tr -d ' ')
echo "Total jobs: $COUNT"

echo "=== Cancelling ==="
$SSH "export PATH=/opt/slurm/bin:\$PATH && scancel $JOB_IDS"
echo "=== Done. Verifying ==="
$SSH "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu -o '%.10i %.80j %.8T' 2>&1 | grep -c 'HG00[4-7]' || echo '0 HG004-7 jobs remaining'"

