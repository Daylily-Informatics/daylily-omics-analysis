#!/usr/bin/env bash
#
# rtg_vcfeval_standalone.sh - Standalone RTG vcfeval concordance checker
#
# Replicates the core logic from workflow/rules/rtg_vcfeval.smk prep_for_concordance_check rule
#
# Usage:
#   ./rtg_vcfeval_standalone.sh <calls_vcf> <calls_tbi> <truth_vcf> <truth_bed> \
#                                <sample_id> <aligner> <snv_caller> <region_name> <output_dir>
#
# Example:
#   ./rtg_vcfeval_standalone.sh \
#       /path/to/sample.vcf.gz \
#       /path/to/sample.vcf.gz.tbi \
#       /fsx/references/.../HG002/giabHC/HG002.vcf.gz \
#       /fsx/references/.../HG002/giabHC/HG002.bed \
#       HG002 \
#       ultimaA \
#       ultimaD \
#       giabHC \
#       /path/to/output/
#
# Environment variables (optional overrides):
#   SDF_PATH     - Path to RTG SDF reference (default: hg38 SDF on /fsx)
#   SUB_THREADS  - Number of threads for rtg vcfeval (default: 7)
#   SCRIPT_DIR   - Path to workflow/scripts/ directory (default: auto-detect)
#
set -euo pipefail

# =============================================================================
# Color output helpers
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Argument parsing
# =============================================================================
if [[ $# -lt 9 ]]; then
    echo "Usage: $0 <calls_vcf> <calls_tbi> <truth_vcf> <truth_bed> <sample_id> <aligner> <snv_caller> <region_name> <output_dir>"
    echo ""
    echo "Arguments:"
    echo "  calls_vcf    - Path to the test/query VCF file (bgzipped)"
    echo "  calls_tbi    - Path to the test VCF index (.tbi)"
    echo "  truth_vcf    - Path to the GIAB truth VCF file"
    echo "  truth_bed    - Path to the high-confidence regions BED file"
    echo "  sample_id    - Sample identifier (e.g., HG002)"
    echo "  aligner      - Aligner name (e.g., bwa2a, strobe, ultimaA)"
    echo "  snv_caller   - SNV caller name (e.g., deep, sentd, oct, ultimaD)"
    echo "  region_name  - Region/subset name (e.g., giabHC, ultima, clinvar_genes)"
    echo "  output_dir   - Output directory path"
    exit 1
fi

CALLS_VCF="$1"
CALLS_TBI="$2"
TRUTH_VCF="$3"
TRUTH_BED="$4"
SAMPLE_ID="$5"
ALIGNER="$6"
SNV_CALLER="$7"
REGION_NAME="$8"
OUTPUT_DIR="$9"

# =============================================================================
# Environment defaults (matching Snakemake config)
# =============================================================================
: "${SDF_PATH:=/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta.sdf}"
: "${SUB_THREADS:=7}"
: "${TMPDIR:=/fsx/scratch}"

# Auto-detect script directory (for parse-vcfeval-summary.py)
SCRIPT_DIR="${SCRIPT_DIR:-}"
if [[ -z "$SCRIPT_DIR" ]]; then
    # Try to find workflow/scripts relative to this script's location
    THIS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "${THIS_SCRIPT_DIR}/../workflow/scripts" ]]; then
        SCRIPT_DIR="${THIS_SCRIPT_DIR}/../workflow/scripts"
    elif [[ -d "./workflow/scripts" ]]; then
        SCRIPT_DIR="./workflow/scripts"
    else
        log_error "Cannot find workflow/scripts directory. Set SCRIPT_DIR environment variable."
        exit 1
    fi
fi

# =============================================================================
# Input validation
# =============================================================================
log_info "Validating inputs..."

declare -A FILES_TO_CHECK=(
    ["Calls VCF"]="$CALLS_VCF"
    ["Calls TBI"]="$CALLS_TBI"
    ["Truth VCF"]="$TRUTH_VCF"
    ["Truth BED"]="$TRUTH_BED"
    ["SDF Reference"]="$SDF_PATH"
    ["Parse script"]="${SCRIPT_DIR}/parse-vcfeval-summary.py"
)

MISSING=0
for desc in "${!FILES_TO_CHECK[@]}"; do
    path="${FILES_TO_CHECK[$desc]}"
    if [[ ! -e "$path" ]]; then
        log_error "$desc not found: $path"
        MISSING=1
    fi
done

if [[ $MISSING -eq 1 ]]; then
    exit 1
fi

# Check rtg is available
if ! command -v rtg &> /dev/null; then
    log_error "'rtg' command not found. Ensure RTG Tools is installed and in PATH."
    log_info "Hint: conda activate rtgtools or similar"
    exit 1
fi

log_info "All inputs validated."

# =============================================================================
# Setup output directories
# =============================================================================
VCFEVAL_OUT="${OUTPUT_DIR}/_${REGION_NAME}"
LOG_DIR="${OUTPUT_DIR}/logs"
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"

LOG_FILE="${LOG_DIR}/${SAMPLE_ID}.${ALIGNER}.${SNV_CALLER}.${REGION_NAME}.concordance.log"
ERR_A="${OUTPUT_DIR}/concordance_a.err"
ERR_B="${OUTPUT_DIR}/concordance_b.err"

log_info "Output directory: $OUTPUT_DIR"
log_info "RTG vcfeval output: $VCFEVAL_OUT"
log_info "Log file: $LOG_FILE"

# =============================================================================
# Clean previous run if exists
# =============================================================================
if [[ -d "$VCFEVAL_OUT" ]]; then
    log_warn "Removing previous output: $VCFEVAL_OUT"
    rm -rf "$VCFEVAL_OUT"
fi

# =============================================================================
# Run RTG vcfeval
# =============================================================================
log_info "Running rtg vcfeval..."
log_info "  Calls VCF:  $CALLS_VCF"
log_info "  Truth VCF:  $TRUTH_VCF"
log_info "  Truth BED:  $TRUTH_BED"
log_info "  SDF:        $SDF_PATH"
log_info "  Threads:    $SUB_THREADS"

RTG_CMD="rtg vcfeval \
    --decompose \
    --squash-ploidy \
    --ref-overlap \
    -e ${TRUTH_BED} \
    -b ${TRUTH_VCF} \
    -c ${CALLS_VCF} \
    -o ${VCFEVAL_OUT} \
    -t ${SDF_PATH} \
    --threads ${SUB_THREADS}"

echo "Command: $RTG_CMD" >> "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"

if $RTG_CMD >> "$ERR_A" 2>&1; then
    log_info "rtg vcfeval completed successfully."
else
    log_error "rtg vcfeval failed. Check $ERR_A for details."
    exit 1
fi

# =============================================================================
# Verify vcfeval output
# =============================================================================
SUMMARY_FILE="${VCFEVAL_OUT}/summary.txt"
if [[ ! -f "$SUMMARY_FILE" ]]; then
    log_error "vcfeval summary.txt not found at: $SUMMARY_FILE"
    exit 1
fi

log_info "vcfeval summary:"
cat "$SUMMARY_FILE"

# =============================================================================
# Parse results with parse-vcfeval-summary.py
# =============================================================================
log_info "Parsing vcfeval results..."

# Mean depth placeholder (not calculated in standalone mode)
ALLVAR_MEAN_DP="na"

# Output summary file path
PARSED_SUMMARY="${VCFEVAL_OUT}/${SAMPLE_ID}_${REGION_NAME}_summary.txt"

PARSE_CMD="python ${SCRIPT_DIR}/parse-vcfeval-summary.py \
    ${SUMMARY_FILE} \
    ${SAMPLE_ID} \
    ${TRUTH_BED} \
    ${REGION_NAME} \
    ${SAMPLE_ID} \
    ${PARSED_SUMMARY} \
    ${ALLVAR_MEAN_DP} \
    ${ALIGNER} \
    ${SNV_CALLER}"

echo "Parse command: $PARSE_CMD" >> "$LOG_FILE"

if $PARSE_CMD >> "$ERR_B" 2>&1; then
    log_info "Results parsed successfully."
else
    log_warn "parse-vcfeval-summary.py had issues. Check $ERR_B for details."
fi

# =============================================================================
# Summary output
# =============================================================================
echo ""
log_info "=========================================="
log_info "CONCORDANCE CHECK COMPLETE"
log_info "=========================================="
log_info "Sample:      $SAMPLE_ID"
log_info "Aligner:     $ALIGNER"
log_info "SNV Caller:  $SNV_CALLER"
log_info "Region:      $REGION_NAME"
log_info ""
log_info "Output files:"
log_info "  Summary:   $SUMMARY_FILE"
log_info "  TP VCF:    ${VCFEVAL_OUT}/tp.vcf.gz"
log_info "  FP VCF:    ${VCFEVAL_OUT}/fp.vcf.gz"
log_info "  FN VCF:    ${VCFEVAL_OUT}/fn.vcf.gz"
log_info "  Parsed:    ${PARSED_SUMMARY}"

# Look for .mqc.tsv file (MultiQC compatible)
MQC_FILE=$(find "$VCFEVAL_OUT" -name "*.mqc.tsv" 2>/dev/null | head -1)
if [[ -n "$MQC_FILE" ]]; then
    log_info "  MultiQC:   $MQC_FILE"
fi

log_info ""
log_info "Logs:"
log_info "  Main log:  $LOG_FILE"
log_info "  RTG err:   $ERR_A"
log_info "  Parse err: $ERR_B"

# Create done sentinel
touch "${OUTPUT_DIR}/concordance.done"
log_info ""
log_info "Done sentinel: ${OUTPUT_DIR}/concordance.done"

echo "Completed: $(date)" >> "$LOG_FILE"

