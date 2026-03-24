#!/usr/bin/env bash
set -o pipefail

LOGDIR="/tmp/validate_extensions_logs"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$LOGDIR/report_v2_${TIMESTAMP}.txt"

log() { echo "$1" | tee -a "$REPORT"; }

log "=== VALIDATION REPORT: feat/sentdhiomr-extensions ==="
log "Timestamp: $(date)"
log ""

log "=== SECTION 1: REFERENCE FILE VALIDATION ==="

check_file() {
    local path="$1" label="$2"
    if [ -s "$path" ]; then
        local sz=$(du -sh "$path" 2>/dev/null | cut -f1)
        log "  PASS  $label ($sz)"
    elif [ -e "$path" ]; then
        log "  FAIL  $label (exists but EMPTY)"
    else
        log "  FAIL  $label (MISSING) -> $path"
    fi
}

BDIR="/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles"
check_file "$BDIR/HybridIlluminaONT2.0.bundle" "HybridIlluminaONT2.0.bundle (main hybrid model)"
check_file "$BDIR/SentieonIlluminaWGS2.2.bundle" "SegDup SR model"
check_file "$BDIR/DNAscopeONT2.2.bundle" "SegDup LR model"

CHRM="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/chrM"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.fasta" "chrM fasta"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.fasta.fai" "chrM fasta.fai"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta" "chrM shifted fasta"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta.fai" "chrM shifted fasta.fai"
check_file "$CHRM/ShiftBack.chain" "ShiftBack.chain"
check_file "$CHRM/blacklist_sites.hg38.chrM.bed" "chrM blacklist BED"
check_file "/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta" "Main genome fasta"
check_file "/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta.fai" "Main genome fasta.fai"
log ""

log "=== SECTION 2: INITIALIZE EXISTING CLONE ==="
WORK_DIR="/fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis"
cd "$WORK_DIR"
log "  Working dir: $(pwd)"
log "  Git commit: $(git log --oneline -1)"

source dyoainit --project daylily-global 2>&1 | tail -3 | tee -a "$REPORT"
source bin/day_activate slurm hg38_broad 2>&1 | tail -3 | tee -a "$REPORT"
log ""

log "=== SECTION 3: DRY-RUN VALIDATION ==="
TARGETS="produce_sentdhiomr_vcf produce_sentdhiomr_cnv produce_sentdhiomr_segdup produce_sentdhiomr_mito produce_manta"

for target in $TARGETS; do
    log "--- Target: $target ---"
    DRYLOG="$LOGDIR/dryrun_${target}_${TIMESTAMP}.log"
    bash bin/day_run "$target" -n -p >"$DRYLOG" 2>&1
    EXIT_CODE=$?
    log "  Exit code: $EXIT_CODE"
    if grep -q "IndexError" "$DRYLOG"; then
        log "  FAIL  IndexError found"
        grep "IndexError" "$DRYLOG" | head -3 | tee -a "$REPORT"
    else
        log "  PASS  No IndexError"
    fi
    if grep -q "^Job stats:" "$DRYLOG"; then
        log "  Job stats:"
        sed -n '/^Job stats:/,/^total/p' "$DRYLOG" | tee -a "$REPORT"
    fi
    for rule in sentdhiomr_call_cnvs sentdhiomr_merge_sr_bams sentdhiomr_call_segdup sentdhiomr_mito_call sentdhiomr_transfer; do
        grep "    $rule" "$DRYLOG" 2>/dev/null | head -1 | tee -a "$REPORT"
    done
    ERR_CNT=$(grep -ci "error\|exception\|traceback" "$DRYLOG" 2>/dev/null || echo 0)
    WARN_CNT=$(grep -ci "warning" "$DRYLOG" 2>/dev/null || echo 0)
    log "  Errors: $ERR_CNT, Warnings: $WARN_CNT"
    log ""
done

log "=== SECTION 4: CONFIG KEYS VALIDATION ==="
for key in keep_sr_alignment keep_tmp_dirs segdup_sr_model segdup_lr_model segdup_genes mt_fasta mt_shifted_fasta mt_shift_back_chain mt_blacklist_bed; do
    val=$(grep "$key" config/day_profiles/slurm/templates/rule_config.yaml 2>/dev/null | head -1)
    if [ -n "$val" ]; then
        log "  PASS  $key -> $val"
    else
        log "  FAIL  $key (NOT FOUND)"
    fi
done

log ""
log "=== VALIDATION COMPLETE ==="
echo "Report: $REPORT"
echo "Logs: $LOGDIR/dryrun_*"
