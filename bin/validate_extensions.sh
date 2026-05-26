#!/usr/bin/env bash
set -uo pipefail

LOGDIR="/tmp/validate_extensions_logs"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$LOGDIR/report_${TIMESTAMP}.txt"

echo "=== VALIDATION REPORT: feat/sentdhiomr-extensions ===" | tee "$REPORT"
echo "Timestamp: $(date)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

echo "=== SECTION 1: REFERENCE FILE VALIDATION ===" | tee -a "$REPORT"

check_file() {
    local path="$1"
    local label="$2"
    if [ -s "$path" ]; then
        local sz=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "  PASS  $label ($sz)" | tee -a "$REPORT"
    elif [ -e "$path" ]; then
        echo "  FAIL  $label (exists but EMPTY)" | tee -a "$REPORT"
    else
        echo "  FAIL  $label (MISSING) -> $path" | tee -a "$REPORT"
    fi
}

check_dir() {
    local path="$1"
    local label="$2"
    if [ -d "$path" ]; then
        local cnt=$(ls -1 "$path" 2>/dev/null | wc -l)
        echo "  PASS  $label ($cnt items)" | tee -a "$REPORT"
    else
        echo "  FAIL  $label (MISSING DIR) -> $path" | tee -a "$REPORT"
    fi
}

check_dir "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02" "Sentieon 202503.02"
for b in /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/share/SentieonHybridIlluminaONT*; do
    check_file "$b" "HybridIlluminaONT: $(basename $b)"
done
check_file "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/share/SentieonIlluminaWGS2.2.bundle" "SegDup SR model"
check_file "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/share/DNAscopeONT2.3.bundle" "SegDup LR model"

CHRM="/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/chrM"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.fasta" "chrM fasta"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.fasta.fai" "chrM fasta.fai"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta" "chrM shifted fasta"
check_file "$CHRM/Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta.fai" "chrM shifted fasta.fai"
check_file "$CHRM/ShiftBack.chain" "ShiftBack.chain"
check_file "$CHRM/blacklist_sites.hg38.chrM.bed" "chrM blacklist BED"
check_file "/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta" "Main genome fasta"
check_file "/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta.fai" "Main genome fasta.fai"
echo "" | tee -a "$REPORT"

echo "=== SECTION 2: CLONE AND INITIALIZE ===" | tee -a "$REPORT"
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/validate-ext-${TIMESTAMP}"
echo "Cloning to: $ANALYSIS_DIR" | tee -a "$REPORT"
day-clone -t feat/sentdhiomr-extensions -w ssh -d "validate-ext-${TIMESTAMP}" 2>&1 | tail -5 | tee -a "$REPORT"

WORK_DIR="$ANALYSIS_DIR/daylily-omics-analysis"
if [ ! -d "$WORK_DIR" ]; then
    echo "  FAIL  Clone failed: $WORK_DIR" | tee -a "$REPORT"
    echo "=== VALIDATION ABORTED ===" | tee -a "$REPORT"
    exit 1
fi

cd "$WORK_DIR"
echo "  Working dir: $(pwd)" | tee -a "$REPORT"
echo "  Git commit: $(git log --oneline -1)" | tee -a "$REPORT"
source dyoainit --project daylily-global 2>&1 | tail -3 | tee -a "$REPORT"
source bin/day_activate slurm hg38_broad 2>&1 | tail -3 | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

echo "=== SECTION 3: DRY-RUN VALIDATION ===" | tee -a "$REPORT"
TARGETS="produce_sentdhiomr_vcf produce_sentdhiomr_cnv produce_sentdhiomr_segdup produce_sentdhiomr_mito produce_manta"

for target in $TARGETS; do
    echo "--- Target: $target ---" | tee -a "$REPORT"
    DRYLOG="$LOGDIR/dryrun_${target}_${TIMESTAMP}.log"
    bash bin/day_run "$target" -n -p >"$DRYLOG" 2>&1
    EXIT_CODE=$?
    echo "  Exit code: $EXIT_CODE" | tee -a "$REPORT"
    if grep -q "IndexError" "$DRYLOG"; then
        echo "  FAIL  IndexError found" | tee -a "$REPORT"
        grep "IndexError" "$DRYLOG" | head -3 | tee -a "$REPORT"
    else
        echo "  PASS  No IndexError" | tee -a "$REPORT"
    fi
    grep -q "^Job stats:" "$DRYLOG" && sed -n '/^Job stats:/,/^total/p' "$DRYLOG" | tee -a "$REPORT"
    for rule in sentdhiomr_call_cnvs sentdhiomr_merge_sr_bams sentdhiomr_call_segdup sentdhiomr_mito_call sentdhiomr_transfer; do
        grep "    $rule" "$DRYLOG" | head -1 | tee -a "$REPORT" 2>/dev/null
    done
    ERR_CNT=$(grep -ci "error\|exception\|traceback" "$DRYLOG" 2>/dev/null || echo 0)
    WARN_CNT=$(grep -ci "warning" "$DRYLOG" 2>/dev/null || echo 0)
    echo "  Errors: $ERR_CNT, Warnings: $WARN_CNT" | tee -a "$REPORT"
    echo "" | tee -a "$REPORT"
done

echo "=== SECTION 4: CONFIG KEYS VALIDATION ===" | tee -a "$REPORT"
for key in keep_sr_alignment keep_tmp_dirs segdup_sr_model segdup_lr_model segdup_genes mt_fasta mt_shifted_fasta mt_shift_back_chain mt_blacklist_bed; do
    val=$(grep "$key" config/day_profiles/slurm/templates/rule_config.yaml 2>/dev/null | head -1)
    if [ -n "$val" ]; then
        echo "  PASS  $key -> $val" | tee -a "$REPORT"
    else
        echo "  FAIL  $key (NOT FOUND)" | tee -a "$REPORT"
    fi
done

echo "" | tee -a "$REPORT"
echo "=== VALIDATION COMPLETE ===" | tee -a "$REPORT"
echo "Report: $REPORT"
echo "Logs: $LOGDIR/dryrun_*"
