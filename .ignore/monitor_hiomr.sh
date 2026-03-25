#!/bin/bash
SSH="ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@35.85.81.27"
for i in $(seq 1 30); do
  sleep 300
  echo "============================================"
  echo "=== CHECK $i  $(date) ==="
  RESULT=$($SSH "grep 'steps.*done' /tmp/hiomr_full.log | tail -1; echo '---ERRORS---'; grep -c 'Error in rule' /tmp/hiomr_full.log; echo '---QUEUE---'; bash -l -c 'squeue -u ubuntu -o \"%.8i %.6t %.50j\" 2>/dev/null | grep -E \" R | PD | CF \" | head -10'; echo '---ALIVE---'; pgrep -f snakemake >/dev/null 2>&1 && echo YES || echo NO; echo '---LASTRULE---'; grep -oP 'rule \S+' /tmp/hiomr_full.log | tail -1" 2>/dev/null)
  echo "$RESULT"
  echo "$RESULT" | grep -q '100%) done' && echo "*** PIPELINE COMPLETE ***" && exit 0
  ALIVE=$(echo "$RESULT" | grep -A1 '\-\-\-ALIVE' | tail -1)
  ERRS=$(echo "$RESULT" | grep -A1 '\-\-\-ERRORS' | tail -1)
  if [ "$ALIVE" = "NO" ] && [ "$ERRS" != "0" ]; then
    echo "*** PIPELINE DIED WITH ERRORS ***"
    $SSH "grep -A5 'Error in rule' /tmp/hiomr_full.log | tail -20" 2>/dev/null
    exit 1
  fi
  if [ "$ALIVE" = "NO" ]; then
    echo "*** PIPELINE NOT RUNNING ***"
    $SSH "tail -5 /tmp/hiomr_full.log" 2>/dev/null
    exit 0
  fi
done
echo "=== MONITOR TIMED OUT (150 min) ==="
