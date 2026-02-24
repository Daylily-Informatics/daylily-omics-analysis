#!/usr/bin/env bash
set -euo pipefail

ILMN_DIR="/fsx/analysis_results/ubuntu/pg_ilmn_1x_test_20260222/daylily-omics-analysis"
UG_DIR="/fsx/analysis_results/ubuntu/pg_ug_1x_test_20260222/daylily-omics-analysis"

# Fix samples.tsv for ILMN (hg38 truth paths)
printf 'SAMPLEID\tSAMPLESOURCE\tSAMPLECLASS\tBIOLOGICAL_SEX\tCONCORDANCE_CONTROL_PATH\tIS_POSITIVE_CONTROL\tIS_NEGATIVE_CONTROL\tSAMPLE_TYPE\tTUM_NRM_SAMPLEID_MATCH\tEXTERNAL_SAMPLE_ID\tN_X\tN_Y\tTRUTH_DATA_DIR\n' > "$ILMN_DIR/config/samples.tsv"
printf 'HG003\tblood\tresearch\tmale\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\ttrue\tfalse\tblood\tna\tHG003\t1\t1\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\n' >> "$ILMN_DIR/config/samples.tsv"
echo "ILMN samples.tsv fixed"

# Fix samples.tsv for UG
printf 'SAMPLEID\tSAMPLESOURCE\tSAMPLECLASS\tBIOLOGICAL_SEX\tCONCORDANCE_CONTROL_PATH\tIS_POSITIVE_CONTROL\tIS_NEGATIVE_CONTROL\tSAMPLE_TYPE\tTUM_NRM_SAMPLEID_MATCH\tEXTERNAL_SAMPLE_ID\tN_X\tN_Y\tTRUTH_DATA_DIR\n' > "$UG_DIR/config/samples.tsv"
printf 'HG003\tblood\tresearch\tmale\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\ttrue\tfalse\tblood\tna\tHG003\t1\t1\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\n' >> "$UG_DIR/config/samples.tsv"
echo "UG samples.tsv fixed"

# Kill old tmux sessions
tmux kill-session -t pg_ilmn_1x 2>/dev/null || true
tmux kill-session -t pg_ug_1x 2>/dev/null || true
echo "Old tmux sessions killed"

# Re-create Illumina 1x tmux session
tmux new-session -d -s pg_ilmn_1x
tmux send-keys -t pg_ilmn_1x "cd $ILMN_DIR && source dyoainit && source bin/day_activate slurm hg38 && bash bin/day_run produce_pangenome_sr_vcf -p -j 1 -k -T 1" Enter
echo "Illumina 1x re-launched in tmux pg_ilmn_1x"

# Re-create Ultima 1x tmux session
tmux new-session -d -s pg_ug_1x
tmux send-keys -t pg_ug_1x "cd $UG_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_pangenome_ug_vcf -p -j 1 -k -T 1" Enter
echo "Ultima 1x re-launched in tmux pg_ug_1x"

echo "DONE"

