#!/bin/bash
source ~/.bashrc
export PATH=/opt/slurm/bin:$PATH
squeue -u ubuntu --format='%.8i %.9P %.40j %.8T %.10M %.4C' | head -40

