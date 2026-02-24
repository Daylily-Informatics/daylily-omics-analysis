#!/bin/bash
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
SAMPLE="HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ"

# find the transfer log
find "$ANALYSIS_DIR/results/" -name "*transfer*log" -type f 2>/dev/null | head -5

# Also check slurm output for job 6024
find "$ANALYSIS_DIR" -name "slurm-6024*" -type f 2>/dev/null | head -5
find "$ANALYSIS_DIR/.snakemake" -name "*6024*" -type f 2>/dev/null | head -5

# Check for any recent log files
find "$ANALYSIS_DIR/results/" -path "*sentdhiomr*" -name "*.log" -newer "$ANALYSIS_DIR/results/day" -type f 2>/dev/null | head -10

