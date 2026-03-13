#!/bin/bash
set -euo pipefail
source ~/.bashrc

TS=$(date +%Y%m%d_%H%M%S)
ANALYSIS_NAME="hiom_std_chr21_${TS}"

echo "=== Cloning repo to ${ANALYSIS_NAME} ==="
day-clone -t feat/modular-hybrid-workflows -w ssh -d "${ANALYSIS_NAME}"

ADIR="/fsx/analysis_results/ubuntu/${ANALYSIS_NAME}/daylily-omics-analysis"
if [ ! -d "$ADIR" ]; then
    echo "ERROR: Expected dir not found: $ADIR"
    ADIR=$(find /fsx/analysis_results/ubuntu/ -maxdepth 2 -name "daylily-omics-analysis" -newer /tmp/setup_marker 2>/dev/null | head -1)
    if [ -z "$ADIR" ]; then
        echo "FATAL: Cannot find cloned analysis dir"
        exit 1
    fi
    echo "Found at: $ADIR"
fi
cd "$ADIR"

echo "=== Setting up test manifests (SR3x-ONT1x only) ==="
cp .test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/samples.tsv config/
head -1 .test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/units.tsv > config/units.tsv
grep 'SR3x-ONT1x' .test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/units.tsv >> config/units.tsv

echo "=== units.tsv content ==="
cat config/units.tsv

echo "=== Limiting sentdhio chrms to chr21 ==="
sed -i 's/hg38_broad_sentdhio_chrms: "1-24"/hg38_broad_sentdhio_chrms: "21"/' config/day_profiles/slurm/templates/rule_config.yaml
grep sentdhio_chrms config/day_profiles/slurm/templates/rule_config.yaml

echo "SETUP_DONE=${ADIR}"

