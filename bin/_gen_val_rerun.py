#!/usr/bin/env python3
"""Generate the validation re-run script for headnode with proper ONT data."""

ANALYSIS_DIR = "/fsx/analysis_results/ubuntu/validate-extensions-20260323/daylily-omics-analysis"

script = f"""#!/usr/bin/env bash
set -o pipefail

ANALYSIS_DIR="{ANALYSIS_DIR}"
LOG_DIR="/tmp/val_logs"
mkdir -p "$LOG_DIR"

cd "$ANALYSIS_DIR" || exit 1

# --- Step 1: Pull latest code ---
echo "=== Pulling latest code at $(date) ==="
git fetch origin feat/sentdhiomr-extensions
git checkout feat/sentdhiomr-extensions
git reset --hard origin/feat/sentdhiomr-extensions
echo "Git HEAD: $(git log --oneline -1)"

# --- Step 2: Backup and install new manifests ---
echo "=== Installing new manifests ==="
cp config/samples.tsv config/samples.tsv.bak.pre_rerun 2>/dev/null || true
cp config/units.tsv config/units.tsv.bak.pre_rerun 2>/dev/null || true
cp /tmp/val_samples.tsv config/samples.tsv
cp /tmp/val_units_3x.tsv config/units.tsv
echo "samples.tsv: $(wc -l < config/samples.tsv) lines"
echo "units.tsv: $(wc -l < config/units.tsv) lines"
echo "Units:"
cut -f3 config/units.tsv | tail -n +2

# --- Step 3: Clean stale results ---
echo "=== Cleaning stale results ==="
rm -rf results/day/hg38_broad/R0-* results/day/hg38_broad/R1-* results/day/hg38_broad/R63-* 2>/dev/null || true

# --- Step 4: Initialize and activate ---
echo "=== Initializing daylily CLI ==="
eval "$(conda shell.bash hook)"
conda activate DAY-EC 2>/dev/null || true
source dyoainit --project daylily-global
source bin/day_activate slurm hg38_broad
set -u  # re-enable after env init

# --- Step 5: Dry-run first ---
echo "=== Phase 0: Dry-run produce_sentdhiomr_vcf ==="
bash bin/day_run produce_sentdhiomr_vcf -n -p -j 2 -k -T 1 2>&1 | tee "$LOG_DIR/rerun_dryrun.log"
DRY_RC=$?
echo "DRY RUN RETURN CODE: $DRY_RC"

if [ "$DRY_RC" -ne 0 ]; then
    echo "ERROR: Dry run failed. Aborting."
    exit 1
fi

# --- Step 6: Real run — all extension targets ---
echo "=== Phase 1: Real run at $(date) ==="
bash bin/day_run produce_sentdhiomr_vcf produce_sentdhiomr_cnv produce_sentdhiomr_segdup produce_sentdhiomr_mito -p -j 4 -k -T 1 2>&1 | tee "$LOG_DIR/rerun_phase1.log"
P1_RC=$?
echo "PHASE 1 RETURN CODE: $P1_RC"

echo "=== Validation re-run complete at $(date) ==="
echo "Phase 1 RC: $P1_RC"
"""

with open("/tmp/val_rerun.sh", "w") as f:
    f.write(script)
print(f"Script written: {len(script)} bytes")

