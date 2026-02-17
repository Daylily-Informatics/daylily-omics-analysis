#!/bin/bash
# Run all 15 3x stress tests for daylily workflows
set -e
BASE=/fsx/analysis_results/ubuntu

echo "=== Removing old test directories ==="
cd $BASE
for d in test-*; do
    if [[ -d "$d" ]]; then
        rm -rf "$d"
    fi
done
echo "Cleaned"

echo ""
echo "=== Cloning 5 singleton tests ==="
for test in ont ilmn pb ug roche; do
    day-clone -w ssh -t feat/modular-hybrid-workflows -d test-${test}-solo-3x 2>&1 | grep "Location" | head -1
done

echo ""
echo "=== Cloning 10 hybrid tests ==="
for test in hybrid-cli-ilmn-ont hybrid-cli-ug-ont hybrid-mod-ilmn-ont hybrid-mod-ug-ont hybrid-cli-ilmn-pb hybrid-mod-ilmn-pb hybrid-cli-ug-pb hybrid-mod-ug-pb hybrid-mod-roche-ont hybrid-mod-roche-pb; do
    day-clone -w ssh -t feat/modular-hybrid-workflows -d test-${test}-3x 2>&1 | grep "Location" | head -1
done

echo ""
echo "=== $(ls -d $BASE/test-* 2>/dev/null | wc -l) directories cloned ==="

