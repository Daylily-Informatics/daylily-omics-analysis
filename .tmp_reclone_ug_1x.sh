#!/usr/bin/env bash
set -euo pipefail

UG_DIR="/fsx/analysis_results/ubuntu/pg_ug_1x_test_20260222"

# Remove old dir
rm -rf "$UG_DIR"
echo "Removed old UG dir"

# Clone fresh
day-clone -t feat/modular-hybrid-workflows -w ssh -d pg_ug_1x_test_20260222
echo "Cloned fresh UG dir"

# Verify the CRAM block is gone from the new clone
if grep -q "Preserve CRAM" "$UG_DIR/daylily-omics-analysis/workflow/rules/sentieon_pangenome_ug.smk"; then
    echo "ERROR: CRAM preservation block still present in new clone"
    exit 1
else
    echo "CONFIRMED: CRAM preservation block removed"
fi

# Write units.tsv
printf 'RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\tULTIMA_CRAM_SNV_CALLER\tSAMPLEUSE\tBWA_KMER\tDOWNSAMPLE_PCT\n' > "$UG_DIR/daylily-omics-analysis/config/units.tsv"
printf 'R1x\tHG003\tD0\t0\tD0\tPCR-FREE\tUG\tULTIMA\tna\tna\t/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_1x.cleaned.cram\tug\tug\tposControl\t19\tna\n' >> "$UG_DIR/daylily-omics-analysis/config/units.tsv"
echo "units.tsv written: $(wc -l < "$UG_DIR/daylily-omics-analysis/config/units.tsv") lines"

# Write samples.tsv
printf 'SAMPLEID\tSAMPLESOURCE\tSAMPLECLASS\tBIOLOGICAL_SEX\tCONCORDANCE_CONTROL_PATH\tIS_POSITIVE_CONTROL\tIS_NEGATIVE_CONTROL\tSAMPLE_TYPE\tTUM_NRM_SAMPLEID_MATCH\tEXTERNAL_SAMPLE_ID\tN_X\tN_Y\tTRUTH_DATA_DIR\n' > "$UG_DIR/daylily-omics-analysis/config/samples.tsv"
printf 'HG003\tblood\tresearch\tmale\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\ttrue\tfalse\tblood\tna\tHG003\t1\t1\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\n' >> "$UG_DIR/daylily-omics-analysis/config/samples.tsv"
echo "samples.tsv written: $(wc -l < "$UG_DIR/daylily-omics-analysis/config/samples.tsv") lines"

# Launch in tmux
tmux new-session -d -s pg_ug_1x
tmux send-keys -t pg_ug_1x "cd $UG_DIR/daylily-omics-analysis && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_pangenome_ug_vcf -p -j 1 -k -T 1" Enter
echo "Ultima 1x launched in tmux pg_ug_1x"
echo "DONE"

