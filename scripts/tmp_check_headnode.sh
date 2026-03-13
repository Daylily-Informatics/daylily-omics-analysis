#!/bin/bash
# Check headnode test status via SSH
SSH="ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=60 -o ServerAliveInterval=10 ubuntu@44.231.76.175"

echo "=== TMUX SESSIONS ==="
$SSH "tmux ls 2>/dev/null || echo 'No tmux sessions'"

echo ""
echo "=== SLURM QUEUE ==="
$SSH "squeue -u ubuntu --format='%.8i %.2t %.55j %.10M' 2>/dev/null | head -25"

echo ""
echo "=== TMUX PANE STATUS ==="
for s in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x t3-hybrid-mod-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x t5-hybrid-mod-ug-ont-3x; do
    echo "---------- $s ----------"
    $SSH "tmux capture-pane -t $s -p -S -10 2>/dev/null | tail -6" 2>/dev/null
    echo ""
done

echo "=== SNAKEMAKE PROCS ==="
$SSH "ps aux | grep 'snakemake.*produce' | grep -v grep | awk '{print \$NF}'" 2>/dev/null

