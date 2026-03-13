#!/usr/bin/env bash
set -euo pipefail

BASEDIR="/fsx/analysis_results/ubuntu"
DIRNAME="pg_ilmn_conc_20260222"
WORKDIR="$BASEDIR/$DIRNAME/daylily-omics-analysis"
TMUX_SESSION="pg_ilmn_conc"
DSDIR="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007"

# Clean if exists
rm -rf "$BASEDIR/$DIRNAME"
echo "Cleaned old dir (if any)"

# Clone fresh
day-clone -t feat/modular-hybrid-workflows -w ssh -d "$DIRNAME"
echo "Cloned to $WORKDIR"

# Verify CRAM block is gone
if grep -q "Preserve CRAM" "$WORKDIR/workflow/rules/sentieon_pangenome_shortreads.smk"; then
    echo "ERROR: CRAM preservation block still present"; exit 1
fi
echo "CONFIRMED: no CRAM block in pangenome_sr rule"

# Write units.tsv — 4 rows: 7x, 10x, 20x, 30x
UNITS="$WORKDIR/config/units.tsv"
HDR="RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\tULTIMA_CRAM_SNV_CALLER\tSAMPLEUSE\tBWA_KMER\tDOWNSAMPLE_PCT"
printf "${HDR}\n" > "$UNITS"

# 7x (downsampled)
printf "R7x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t${DSDIR}/downsampled/HG003_7x_R1.fastq.gz\t${DSDIR}/downsampled/HG003_7x_R2.fastq.gz\tna\tna\tna\tposControl\t19\tna\n" >> "$UNITS"
# 10x (downsampled)
printf "R10x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t${DSDIR}/downsampled/HG003_10x_R1.fastq.gz\t${DSDIR}/downsampled/HG003_10x_R2.fastq.gz\tna\tna\tna\tposControl\t19\tna\n" >> "$UNITS"
# 20x (downsampled)
printf "R20x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t${DSDIR}/downsampled/HG003_20x_R1.fastq.gz\t${DSDIR}/downsampled/HG003_20x_R2.fastq.gz\tna\tna\tna\tposControl\t19\tna\n" >> "$UNITS"
# 30x (full depth — NOT in downsampled/)
printf "R30x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t${DSDIR}/HG003_30x_R1.fastq.gz\t${DSDIR}/HG003_30x_R2.fastq.gz\tna\tna\tna\tposControl\t19\tna\n" >> "$UNITS"

echo "units.tsv: $(wc -l < "$UNITS") lines"
cat "$UNITS"

# Write samples.tsv
SAMPS="$WORKDIR/config/samples.tsv"
printf 'SAMPLEID\tSAMPLESOURCE\tSAMPLECLASS\tBIOLOGICAL_SEX\tCONCORDANCE_CONTROL_PATH\tIS_POSITIVE_CONTROL\tIS_NEGATIVE_CONTROL\tSAMPLE_TYPE\tTUM_NRM_SAMPLEID_MATCH\tEXTERNAL_SAMPLE_ID\tN_X\tN_Y\tTRUTH_DATA_DIR\n' > "$SAMPS"
printf 'HG003\tblood\tresearch\tmale\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\ttrue\tfalse\tblood\tna\tHG003\t1\t1\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\n' >> "$SAMPS"
echo "samples.tsv: $(wc -l < "$SAMPS") lines"

# Kill old tmux if exists
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

# Launch
tmux new-session -d -s "$TMUX_SESSION"
tmux send-keys -t "$TMUX_SESSION" "cd $WORKDIR && source dyoainit && source bin/day_activate slurm hg38 && bash bin/day_run produce_snv_concordances -p -j 4 -k -T 1 --config aligners=\"['pangenome_sr']\" dedupers=\"['spmd']\" snv_callers=\"['sentpg']\"" Enter
echo "Launched in tmux session: $TMUX_SESSION"
echo "DONE"

