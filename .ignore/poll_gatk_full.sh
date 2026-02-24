#!/usr/bin/env bash
set -uo pipefail

SSH_CMD="ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@34.209.187.6"
POLL_INTERVAL=1200
LOGFILE="/tmp/poll_gatk_full.log"
TMUX_SESSION="gatk_ilmn_full_9units"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }

log "=== GATK full 9-unit poller started (every ${POLL_INTERVAL}s / 20min) ==="

while true; do
    TMUX_OUT=$($SSH_CMD "source ~/.bashrc && tmux capture-pane -t $TMUX_SESSION -p -S -50 2>/dev/null" 2>/dev/null || echo "TMUX_ERROR")

    if echo "$TMUX_OUT" | grep -q "RETURN CODE: 0"; then
        log "SUCCESS: GATK full 9-unit run completed (RETURN CODE: 0)"
        say "GATK full 9 unit run completed successfully."
        exit 0
    fi

    if echo "$TMUX_OUT" | grep -qE "RETURN CODE: [1-9]"; then
        RC=$(echo "$TMUX_OUT" | grep -oE "RETURN CODE: [0-9]+" | tail -1)
        log "FAILURE: $RC"
        say "GATK full 9 unit run FAILED. $RC. Check the log."
        exit 1
    fi

    QUEUE=$($SSH_CMD "source ~/.bashrc && export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu -o '%.8i %.50j %.8T %.10M' 2>/dev/null | grep -iE 'gatk|doppelmark|sentieon_bwa.*I2-HG003|alignstat.*I2-HG003|prep_for.*I2-HG003|rtg.*I2-HG003' | head -20" 2>/dev/null || echo "SSH_ERROR")
    GATK_COUNT=$(echo "$QUEUE" | grep -c '[A-Z]' 2>/dev/null || echo "0")
    TOTAL=$($SSH_CMD "source ~/.bashrc && export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo "?")

    log "--- Poll at $(date) ---"
    log "GATK jobs ($GATK_COUNT):"
    log "$QUEUE"
    log "Cluster total: $TOTAL"

    if [ "$GATK_COUNT" = "0" ] || [ -z "$GATK_COUNT" ]; then
        say "GATK full run poll: no jobs in slurm queue. Waiting for tmux final status."
    else
        say "GATK full run poll: $GATK_COUNT jobs active. Cluster total $TOTAL."
    fi

    sleep $POLL_INTERVAL
done

