#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pangenome_sr_dryrun_20260221/daylily-omics-analysis"
MANIFEST_DIR="${ANALYSIS_DIR}/.test_data/data"

# Verify 3x FASTQs exist
R1_3x="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R1.fastq.gz"
R2_3x="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_3x_R2.fastq.gz"
R1_30x="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R1.fastq.gz"
R2_30x="/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R2.fastq.gz"

for f in "$R1_3x" "$R2_3x" "$R1_30x" "$R2_30x"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Missing FASTQ: $f"
    exit 1
  fi
done
echo "All FASTQs verified."

# --- samples.tsv (one HG003 entry) ---
cat > "${MANIFEST_DIR}/hg003_30x_3x_hg38.samples.tsv" <<'HEADER'
SAMPLEID	SAMPLESOURCE	SAMPLECLASS	BIOLOGICAL_SEX	CONCORDANCE_CONTROL_PATH	IS_POSITIVE_CONTROL	IS_NEGATIVE_CONTROL	SAMPLE_TYPE	TUM_NRM_SAMPLEID_MATCH	EXTERNAL_SAMPLE_ID	N_X	N_Y	TRUTH_DATA_DIR
HEADER

printf 'HG003\tblood\tresearch\tmale\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\ttrue\tfalse\tblood\tna\tHG003\t1\t1\t/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/\n' \
  >> "${MANIFEST_DIR}/hg003_30x_3x_hg38.samples.tsv"

# --- units.tsv (two rows: R30x and R3x) ---
cat > "${MANIFEST_DIR}/hg003_30x_3x_hg38.units.tsv" <<'HEADER'
RUNID	SAMPLEID	EXPERIMENTID	LANEID	BARCODEID	LIBPREP	SEQ_VENDOR	SEQ_PLATFORM	ILMN_R1_PATH	ILMN_R2_PATH	PACBIO_R1_PATH	PACBIO_R2_PATH	ONT_R1_PATH	ONT_R2_PATH	UG_R1_PATH	UG_R2_PATH	SUBSAMPLE_PCT	ILMN_TRIM_READ_LENGTH	SAMPLEUSE	BWA_KMER	DEEP_MODEL	ULTIMA_CRAM	ULTIMA_CRAM_ALIGNER	ULTIMA_CRAM_SNV_CALLER	ONT_CRAM	ONT_CRAM_ALIGNER	ONT_CRAM_SNV_CALLER	PB_BAM	PB_BAM_ALIGNER	PB_BAM_SNV_CALLER
HEADER

# 30x row
printf 'R30x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t%s\t%s\t\t\t\t\t\t\t\t\tposControl\t19\t\t\t\t\t\t\t\t\t\t\n' \
  "$R1_30x" "$R2_30x" \
  >> "${MANIFEST_DIR}/hg003_30x_3x_hg38.units.tsv"

# 3x row
printf 'R3x\tHG003\tD0\t0\tD0\tPCR-FREE\tILMN\tNOVASEQ\t%s\t%s\t\t\t\t\t\t\t\t\tposControl\t19\t\t\t\t\t\t\t\t\t\t\n' \
  "$R1_3x" "$R2_3x" \
  >> "${MANIFEST_DIR}/hg003_30x_3x_hg38.units.tsv"

# Copy into config/
cp "${MANIFEST_DIR}/hg003_30x_3x_hg38.samples.tsv" "${ANALYSIS_DIR}/config/samples.tsv"
cp "${MANIFEST_DIR}/hg003_30x_3x_hg38.units.tsv"   "${ANALYSIS_DIR}/config/units.tsv"

# Update global.yaml
cd "$ANALYSIS_DIR"
sed -i "s|remote_samples_table:.*|remote_samples_table: \".test_data/data/hg003_30x_3x_hg38.samples.tsv\"|" config/global.yaml
sed -i "s|remote_units_table:.*|remote_units_table: \".test_data/data/hg003_30x_3x_hg38.units.tsv\"|"     config/global.yaml

echo "=== samples.tsv ==="
cat config/samples.tsv
echo ""
echo "=== units.tsv ==="
cat config/units.tsv
echo ""
echo "=== global.yaml refs ==="
grep -E "remote_samples|remote_units" config/global.yaml
echo "=== DONE ==="

