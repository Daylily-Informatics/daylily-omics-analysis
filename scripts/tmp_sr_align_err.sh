#!/bin/bash
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no ubuntu@44.231.76.175 'find /fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis/logs/slurm -name "*sr_align*err*" 2>/dev/null | head -3'

