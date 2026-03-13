#!/usr/bin/env bash
#
# Verify ensemble workflow integration
#
# Usage: bash bin/verify_ensemble_integration.sh

set -euo pipefail

echo "=== Ensemble Workflow Integration Verification ==="
echo ""

# Check if ensemble rule file exists
echo "1. Checking ensemble rule file..."
if [ -f "workflow/rules/hyb_ensemble_multi_platform.smk" ]; then
    echo "   ✓ hyb_ensemble_multi_platform.smk exists"
else
    echo "   ✗ hyb_ensemble_multi_platform.smk NOT FOUND"
    exit 1
fi

# Check if ensemble is included in Snakefile
echo ""
echo "2. Checking Snakefile includes ensemble rules..."
if grep -q "hyb_ensemble_multi_platform.smk" workflow/Snakefile; then
    echo "   ✓ Ensemble rules included in Snakefile"
else
    echo "   ✗ Ensemble rules NOT included in Snakefile"
    exit 1
fi

# Check if ensemble is registered in _SNV_CALLER_VALID_ALIGNERS
echo ""
echo "3. Checking ensemble registration in common.smk..."
if grep -q '"ensemble"' workflow/rules/common.smk; then
    echo "   ✓ Ensemble registered in _SNV_CALLER_VALID_ALIGNERS"
else
    echo "   ✗ Ensemble NOT registered in _SNV_CALLER_VALID_ALIGNERS"
    exit 1
fi

# Check if units schema has new columns
echo ""
echo "4. Checking units.schema.yaml for new columns..."
if grep -q "SR_VCF_PATH" workflow/schemas/units.schema.yaml && \
   grep -q "LR_VCF_PATH" workflow/schemas/units.schema.yaml; then
    echo "   ✓ SR_VCF_PATH and LR_VCF_PATH in units schema"
else
    echo "   ✗ New columns NOT in units schema"
    exit 1
fi

# Check if example files exist
echo ""
echo "5. Checking example configuration files..."
if [ -f ".test_data/data/ensemble/README.md" ] && \
   [ -f ".test_data/data/ensemble/units.tsv" ] && \
   [ -f ".test_data/data/ensemble/samples.tsv" ]; then
    echo "   ✓ Example configuration files exist"
else
    echo "   ✗ Example configuration files NOT FOUND"
    exit 1
fi

# Check for target rules
echo ""
echo "6. Checking target rules in ensemble workflow..."
if grep -q "rule produce_ensemble_vcf" workflow/rules/hyb_ensemble_multi_platform.smk && \
   grep -q "rule produce_ensemble_concordances" workflow/rules/hyb_ensemble_multi_platform.smk; then
    echo "   ✓ Target rules defined"
else
    echo "   ✗ Target rules NOT FOUND"
    exit 1
fi

# Check for wildcard constraints
echo ""
echo "7. Checking wildcard constraints..."
if grep -q "ALIGNERS_ENSEMBLE" workflow/rules/hyb_ensemble_multi_platform.smk; then
    echo "   ✓ ALIGNERS_ENSEMBLE defined"
else
    echo "   ✗ ALIGNERS_ENSEMBLE NOT FOUND"
    exit 1
fi

# Check for standard output path pattern
echo ""
echo "8. Checking output path pattern..."
if grep -q 'MDIR.*align.*ddup.*snv.*ensemble' workflow/rules/hyb_ensemble_multi_platform.smk; then
    echo "   ✓ Standard output path pattern used"
else
    echo "   ✗ Standard output path pattern NOT FOUND"
    exit 1
fi

echo ""
echo "=== All Checks Passed! ==="
echo ""
echo "Next steps:"
echo "  1. Test with dry run: dy-r produce_ensemble_vcf -n"
echo "  2. Review .test_data/data/ensemble/README.md for usage examples"
echo "  3. Configure units.tsv with SR_VCF_PATH and LR_VCF_PATH columns"
echo ""

