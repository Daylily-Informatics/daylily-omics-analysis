#!/usr/bin/env bash

# Usage: ./run_concordance.sh <path_to_calls_vcf.gz> <path_to_truth_dir>
# Required env vars:
#   ALIGNER, SNV_CALLER, ALT_NAME, SDF_PATH, OUT_DIR, CLUSTER_SAMPLE, SUB_THREADS

export ALIGNER="ultimaA"
export SNV_CALLER="ultimaD"
export ALT_NAME="HG002"
export SDF_PATH="/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta.sdf/"
export OUT_DIR=$PWD/manual_results/concordance/
mkdir -p "$OUT_DIR"
export CLUSTER_SAMPLE="HG002"
export SUB_THREADS=7


set -euo pipefail

# --- Inputs ---
CVCF="$1"
TRUTH_DIR="$2"
TBI="${CVCF}.tbi"

# --- Required params from environment ---
: "${ALIGNER:?Need ALIGNER set}"
: "${SNV_CALLER:?Need SNV_CALLER set}"
: "${ALT_NAME:?Need ALT_NAME set}"
: "${SDF_PATH:?Need SDF_PATH set}"
: "${OUT_DIR:?Need OUT_DIR set}"
: "${CLUSTER_SAMPLE:?Need CLUSTER_SAMPLE set}"
: "${SUB_THREADS:=7}"

# --- Derived paths ---
SUBD="${ALT_NAME}_$(basename $TRUTH_DIR)"
CVCF_CONV=$(basename $CVCF | tr '.' '_')
CONC_DIR="${OUT_DIR}/${CVCF_CONV}/_${SUBD}"

LOG="${CONC_DIR}/${CLUSTER_SAMPLE}.${ALIGNER}.${SNV_CALLER}.concordance.log"
FOFN="${CONC_DIR}/concordance.fofn"
FIN_CMDS="${CONC_DIR}/concordance.fin.cmds"
DONE_SENTINEL="${CONC_DIR}/concordance.done"
ERR_A="${CONC_DIR}/concordance_a.err"
ERR_B="${CONC_DIR}/concordance_b.err"

mkdir -p "$CONC_DIR"

# --- Initialize files ---
echo "" > "$FOFN"
echo "" > "$FIN_CMDS"

export allvar_mean_dp="na"

# Safety fallback
if [[ -z "$ALIGNER" ]]; then ALIGNER="na"; fi
if [[ -z "$SNV_CALLER" ]]; then SNV_CALLER="na"; fi

# If no valid concordance directory string is set, skip
if [[ ${#CONC_DIR} -le 6 ]]; then
    echo "WARNING: concordance not configured, skipping." >&2
    touch "$DONE_SENTINEL" "${DONE_SENTINEL}.SKIPPED"
    exit 0
fi

# --- Main processing loop ---
BED="${TRUTH_DIR}/${ALT_NAME}.bed"
VCF="${TRUTH_DIR}/${ALT_NAME}.vcf.gz"
SUBD="${ALT_NAME}"

if [[ ! -f "$VCF" || ! -f "$BED" ]]; then
    echo "Missing truth files: $BED or $VCF, skipping" >> "$LOG"
else
    OUT_SUBD="${CONC_DIR}/_${SUBD}_$(basename "${TRUTH_DIR}" | tr '.' '_')"
    rm -rf "$OUT_SUBD" || true

   CMD="rtg vcfeval --decompose --squash-ploidy --ref-overlap -e $BED -b $VCF -c $CVCF -o $OUT_SUBD -t $SDF_PATH --threads $SUB_THREADS"
   FIN="python workflow/scripts/parse-vcfeval-summary.py $OUT_SUBD/summary.txt $CLUSTER_SAMPLE $BED $(basename $TRUTH_DIR) $ALT_NAME $OUT_SUBD/${CLUSTER_SAMPLE}_${SUBD}_summary.txt $allvar_mean_dp $ALIGNER $SNV_CALLER"

    echo "$CMD >> ${CONC_DIR}_a.err 2>&1; $FIN >> ${CONC_DIR}_b.err 2>&1;" >> "$FOFN"
fi

# --- Execute commands ---
cat "$FOFN" | bash >> "$LOG" 2>&1

# --- Finalization ---
touch "$DONE_SENTINEL"
echo "Concordance done for $CLUSTER_SAMPLE" >> "$LOG"
