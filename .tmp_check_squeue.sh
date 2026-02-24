#!/bin/bash
ssh -o ConnectTimeout=30 -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175 '/opt/slurm/bin/squeue -u ubuntu'

