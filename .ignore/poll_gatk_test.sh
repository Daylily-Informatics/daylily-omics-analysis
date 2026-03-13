#!/usr/bin/env bash
set -uo pipefail

SSH_CMD="ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@34.209.187.6"
POLL_INTERVAL=1200
LOGFILE="/tmp/poll_gatk_test.log"
TMUX_SESSION="gatk_ilmn5x_test"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }

log "=== GATK 5x test poller started (every ${POLL_INTERVAL}s / 20min) ==="

while true; do
    TMUX_OUT=$($SSH_CMD "source ~/.bashrc && tmux capture-pane -t $TMUX_SESSION -p -S -50 2>/dev/null" 2>/dev/null || echo "TMUX_ERROR")

    if echo "$TMUX_OUT" | grep -q "RETURN CODE: 0"; then
        log "SUCCESS: GATK 5x test completed (RETURN CODE: 0)"
        say "GATK 5 x test workflow completed successfully. Launching full 9 unit run now."
        exit 0
    fi

    if echo "$TMUX_OUT" | grep -qE "RETURN CODE: [1-9]"; then
        RC=$(echo "$TMUX_OUT" | grep -oE "RETURN CODE: [0-9]+" | tail -1)
        log "FAILURE: $RC"
        say "GATK 5 x test FAILED. $RC. Check the log."
        exit 1
    fi

    QUEUE=$($SSH_CMD "source ~/.bashrc && export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu -o '%.8i %.45j %.8T %.10M' 2>/dev/null | grep -iE 'gatk|doppelmark_dups-I2-HG003-5x|alignstat.*I2-HG003-5x|prep_for.*I2-HG003-5x|rtg.*I2-HG003-5x' | head -15" 2>/dev/null || echo "SSH_ERROR")
    GATK_COUNT=$(echo "$QUEUE" | grep -c '[A-Z]' 2>/dev/null || echo "0")
    TOTAL=$($SSH_CMD "source ~/.bashrc && export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo "?")

    log "--- Poll at $(date) ---"
    log "GATK jobs ($GATK_COUNT):"
    log "$QUEUE"
    log "Cluster total: $TOTAL"

    if [ "$GATK_COUNT" = "0" ] || [ -z "$GATK_COUNT" ]; then
        say "GATK test poll: no jobs in slurm queue. Waiting for tmux final status on next poll."
    else
        say "GATK test poll: $GATK_COUNT jobs active. Cluster total $TOTAL."
    fi

    sleep $POLL_INTERVAL
done

