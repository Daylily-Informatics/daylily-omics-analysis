#!/bin/bash
# Setup script for modular hybrid workflow tests
# Creates test directories using day-clone and copies manifest files
# for testing sentdhiom (Illumina+ONT) and sentdhuom (Ultima+ONT) modular workflows
set -e

source ~/.bashrc

echo "=== Creating modular hybrid test directories ==="

# Illumina+ONT modular (sentdhiom)
cd /fsx/analysis_results/ubuntu
day-clone -d test-hybrid-io-mod-5x -t feat/modular-hybrid-workflows
cd test-hybrid-io-mod-5x/daylily-omics-analysis
cp /fsx/analysis_results/ubuntu/test-hybrid-io-5x-dry/daylily-omics-analysis/config/samples.tsv config/
cp /fsx/analysis_results/ubuntu/test-hybrid-io-5x-dry/daylily-omics-analysis/config/units.tsv config/
echo "Created test-hybrid-io-mod-5x"

# Ultima+ONT modular (sentdhuom)
cd /fsx/analysis_results/ubuntu
day-clone -d test-hybrid-uo-mod-5x -t feat/modular-hybrid-workflows
cd test-hybrid-uo-mod-5x/daylily-omics-analysis
cp /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis/config/samples.tsv config/
cp /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis/config/units.tsv config/
echo "Created test-hybrid-uo-mod-5x"

echo ""
echo "=== Verifying ==="
ls -la /fsx/analysis_results/ubuntu/test-hybrid-io-mod-5x/daylily-omics-analysis/config/*.tsv
ls -la /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis/config/*.tsv

echo ""
echo "=== To run the tests ==="
echo "# Illumina+ONT modular:"
echo "cd /fsx/analysis_results/ubuntu/test-hybrid-io-mod-5x/daylily-omics-analysis"
echo ". dyoainit && dy-a slurm hg38 && dy-r produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -k -j 10"
echo ""
echo "# Ultima+ONT modular:"
echo "cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis"
echo ". dyoainit && dy-a slurm hg38 && dy-r produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -k -j 10"

