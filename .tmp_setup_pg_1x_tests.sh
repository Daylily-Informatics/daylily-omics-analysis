#!/usr/bin/env bash
set -euo pipefail

# --- Clone two fresh analysis dirs for 1x pangenome tests ---

BRANCH="feat/modular-hybrid-workflows"

# 1. Clone for Illumina 1x test
echo "=== Cloning Illumina 1x pangenome test dir ==="
day-clone -t "$BRANCH" -w ssh -d pg_ilmn_1x_test_20260222
ILMN_DIR="/fsx/analysis_results/ubuntu/pg_ilmn_1x_test_20260222/daylily-omics-analysis"
echo "ILMN clone at: $ILMN_DIR"

# 2. Clone for Ultima 1x test
echo "=== Cloning Ultima 1x pangenome test dir ==="
day-clone -t "$BRANCH" -w ssh -d pg_ug_1x_test_20260222
UG_DIR="/fsx/analysis_results/ubuntu/pg_ug_1x_test_20260222/daylily-omics-analysis"
echo "UG clone at: $UG_DIR"

# 3. Write Illumina 1x units.tsv (tab-separated)
echo "=== Writing Illumina units.tsv ==="
printf 'RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\tPACBIO_R1_PATH\tPACBIO_R2_PATH\tONT_R1_PATH\tONT_R2_PATH\tUG_R1_PATH\tUG_R2_PATH\tSUBSAMPLE_PCT\tILMN_TRIM_READ_LENGTH\tSAMPLEUSE\tBWA_KMER\tDEEP_MODEL\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\tULTIMA_CRAM_SNV_CALLER\tONT_CRAM\tONT_CRAM_ALIGNER\tONT_CRAM_SNV_CALLER\tPB_BAM\tPB_BAM_ALIGNER\tPB_BAM_SNV_CALLER\n' > "$ILMN_DIR/config/units.tsv"
printf 'R1x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_1x_R1.fastq.gz\t/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_1x_R2.fastq.gz\t\t\t\t\t\t\t\t\t\tposControl\t19\t\t\t\t\t\t\t\t\t\n' >> "$ILMN_DIR/config/units.tsv"
echo "  -> $(wc -l < "$ILMN_DIR/config/units.tsv") lines"

# 4. Write Ultima 1x units.tsv (tab-separated)
echo "=== Writing Ultima units.tsv ==="
printf 'RUNID\tSAMPLEID\tEXPERIMENTID\tLANEID\tBARCODEID\tLIBPREP\tSEQ_VENDOR\tSEQ_PLATFORM\tILMN_R1_PATH\tILMN_R2_PATH\tPACBIO_R1_PATH\tPACBIO_R2_PATH\tONT_R1_PATH\tONT_R2_PATH\tUG_R1_PATH\tUG_R2_PATH\tSUBSAMPLE_PCT\tILMN_TRIM_READ_LENGTH\tSAMPLEUSE\tBWA_KMER\tDEEP_MODEL\tULTIMA_CRAM\tULTIMA_CRAM_ALIGNER\tULTIMA_CRAM_SNV_CALLER\tONT_CRAM\tONT_CRAM_ALIGNER\tONT_CRAM_SNV_CALLER\tPB_BAM\tPB_BAM_ALIGNER\tPB_BAM_SNV_CALLER\n' > "$UG_DIR/config/units.tsv"
printf 'R1x\tHG003\tD0\t0\tD0\tPCR-FREE\tUG\tULTIMA\t\t\t\t\t\t\t\t\t\t\tposControl\t19\tWGS\t/fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ug/HG003_1x.cleaned.cram\tug\tug\t\t\t\t\t\t\n' >> "$UG_DIR/config/units.tsv"
echo "  -> $(wc -l < "$UG_DIR/config/units.tsv") lines"

# 5. Write samples.tsv for both
echo "=== Writing samples.tsv for both ==="
printf 'sampleid\nHG003\n' > "$ILMN_DIR/config/samples.tsv"
printf 'sampleid\nHG003\n' > "$UG_DIR/config/samples.tsv"

echo ""
echo "=== Setup complete ==="
echo "ILMN dir: $ILMN_DIR"
echo "UG dir:   $UG_DIR"
echo "DONE"

