#!/bin/bash
set -e

echo "=== Staging test data for all 6 tests ==="

# 1. Hybrid Ultima+ONT (uses hg38_broad)
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x/daylily-omics-analysis
cp .test_data/data/hybrid/ultima_ont_5x.samples.tsv config/samples.tsv
cp .test_data/data/hybrid/ultima_ont_5x.units.tsv config/units.tsv
echo "Hybrid Ultima+ONT staged"

# 2. Hybrid Illumina+ONT
cd /fsx/analysis_results/ubuntu/test-hybrid-io-5x/daylily-omics-analysis
cp .test_data/data/hybrid/ilmn_ont_5x.samples.tsv config/samples.tsv
cp .test_data/data/hybrid/ilmn_ont_5x.units.tsv config/units.tsv
echo "Hybrid Illumina+ONT staged"

# 3. ONT only
cd /fsx/analysis_results/ubuntu/test-ont-5x/daylily-omics-analysis
cp .test_data/data/ont/ont_5x.samples.tsv config/samples.tsv
cp .test_data/data/ont/ont_5x.units.tsv config/units.tsv
echo "ONT only staged"

# 4. Illumina only
cd /fsx/analysis_results/ubuntu/test-ilmn-5x/daylily-omics-analysis
cp .test_data/data/ilmn/ilmn_5x.samples.tsv config/samples.tsv
cp .test_data/data/ilmn/ilmn_5x.units.tsv config/units.tsv
echo "Illumina only staged"

# 5. PacBio only
cd /fsx/analysis_results/ubuntu/test-pb-5x/daylily-omics-analysis
cp .test_data/data/pacbio/pb_5x.samples.tsv config/samples.tsv
cp .test_data/data/pacbio/pb_5x.units.tsv config/units.tsv
echo "PacBio only staged"

# 6. Ultima only (uses hg38_broad)
cd /fsx/analysis_results/ubuntu/test-ultima-5x/daylily-omics-analysis
cp .test_data/data/ultima/ultima_5x.samples.tsv config/samples.tsv
cp .test_data/data/ultima/ultima_5x.units.tsv config/units.tsv
echo "Ultima only staged"

echo "=== All test data staged ==="

