#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pacbio-solo-2/daylily-omics-analysis"

echo "=== 1. Slurm logs for sent_snv_pacbio (most recent) ==="
SLURM_DIR="$ANALYSIS_DIR/logs/slurm/sent_snv_pacbio"
ls -lt "$SLURM_DIR/" 2>/dev/null | head -10

echo ""
echo "=== 2. Most recent slurm log content ==="
LATEST_SLURM=$(ls -t "$SLURM_DIR/"* 2>/dev/null | head -1)
if [ -n "$LATEST_SLURM" ]; then
    echo "File: $LATEST_SLURM"
    echo "Size: $(wc -c < "$LATEST_SLURM") bytes"
    echo "--- Last 60 lines ---"
    tail -60 "$LATEST_SLURM"
else
    echo "No slurm logs found"
fi

echo ""
echo "=== 3. Second most recent slurm log ==="
SECOND_SLURM=$(ls -t "$SLURM_DIR/"* 2>/dev/null | sed -n '2p')
if [ -n "$SECOND_SLURM" ]; then
    echo "File: $SECOND_SLURM"
    echo "Size: $(wc -c < "$SECOND_SLURM") bytes"
    echo "--- Last 60 lines ---"
    tail -60 "$SECOND_SLURM"
else
    echo "No second slurm log found"
fi

echo ""
echo "=== 4. Model bundle investigation ==="
echo "--- What bundles exist? ---"
ls -la /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/ 2>/dev/null || echo "Bundles dir not found"
echo ""
echo "--- Search for PacBio bundle ---"
find /fsx/data/cached_envs/sentieon-genomics-202503.02/ -name "*PacBio*" -o -name "*pacbio*" 2>/dev/null || echo "No PacBio bundles found"
echo ""
echo "--- Search for diploid_model ---"
find /fsx/data/cached_envs/sentieon-genomics-202503.02/ -name "diploid_model*" 2>/dev/null || echo "No diploid_model found"

echo ""
echo "=== 5. What model does the config specify? ==="
grep -A5 "sentdpb" "$ANALYSIS_DIR/config/day_profiles/slurm/templates/rule_config.yaml" 2>/dev/null | grep -i model || echo "Config not found"

echo ""
echo "=== 6. Check if rep1 gvcf is truncated (last bytes) ==="
REP1_GVCF="$ANALYSIS_DIR/results/day/hg38/R0-HG002-rep1-0-rep1-PCR-FREE-PACBIO-REVIO/align/sentmm2/snv/sentdpb/vcfs/1-24/R0-HG002-rep1-0-rep1-PCR-FREE-PACBIO-REVIO.sentmm2.sentdpb.1-24.snv.gvcf"
if [ -f "$REP1_GVCF" ]; then
    echo "Last 20 bytes (hex):"
    xxd "$REP1_GVCF" | tail -3
fi

echo ""
echo "=== DONE ==="

