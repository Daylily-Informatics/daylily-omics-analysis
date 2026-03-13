#!/usr/bin/env bash
# Sync the updated workflow .smk files to all test directories that need them
set -e

# Source directory with fixed workflow files (this is a git clone with the fixes)
SOURCE_DIR="/fsx/analysis_results/ubuntu/test-hybrid-mod-ilmn-ont-3x"

BASE_DIR="/fsx/analysis_results/ubuntu"

# The fixed workflow files we need to copy
FIXED_FILES=(
    "workflow/rules/sent_hybrid_ilmn_pb_modular.smk"
    "workflow/rules/sent_hybrid_ug_pb_modular.smk"
    "workflow/rules/sent_hybrid_roche_ont_modular.smk"
    "workflow/rules/sent_hybrid_roche_pb_modular.smk"
)

# Test directories that need the PB or Roche hybrid workflow fixes
TARGET_TESTS=(
    "test-hybrid-cli-ilmn-pb-3x"
    "test-hybrid-mod-ilmn-pb-3x"
    "test-hybrid-cli-ug-pb-3x"
    "test-hybrid-mod-ug-pb-3x"
    "test-hybrid-mod-roche-ont-3x"
    "test-hybrid-mod-roche-pb-3x"
)

# First, update the source directory (which should be a git clone)
echo "=== Updating source directory with latest fixes ==="
cd "${SOURCE_DIR}"
git fetch origin feat/modular-hybrid-workflows || echo "Fetch failed, continuing with existing files"
git reset --hard origin/feat/modular-hybrid-workflows || echo "Reset failed"

echo ""
echo "=== Copying fixed workflow files to target directories ==="
for test in "${TARGET_TESTS[@]}"; do
    test_dir="${BASE_DIR}/${test}"
    if [ -d "$test_dir" ]; then
        echo "Syncing to $test..."
        for file in "${FIXED_FILES[@]}"; do
            if [ -f "${SOURCE_DIR}/${file}" ]; then
                # Ensure target directory exists
                target_subdir=$(dirname "${test_dir}/${file}")
                mkdir -p "$target_subdir"
                cp "${SOURCE_DIR}/${file}" "${test_dir}/${file}"
                echo "  Copied $file"
            fi
        done
    else
        echo "Directory not found: $test_dir"
    fi
done

echo ""
echo "=== Workflow files synced ==="

