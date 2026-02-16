#!/bin/bash
# Run a single dry-run test on the headnode
# Usage: bash -l run_test_on_headnode.sh <test_num>
# This script sources dyoainit internally so shell functions are available

TESTNUM="${1:?Usage: $0 <test_num 1-6>}"
ADIR="/fsx/analysis_results/ubuntu/dryrun-118/daylily-omics-analysis"
cd "$ADIR" || exit 1

# Source dyoainit to get dy-a and dy-r functions
source dyoainit 2>/dev/null
dy-a slurm hg38 2>/dev/null

case "$TESTNUM" in
    1)
        NAME="Hybrid Ultima+ONT"
        cp .test_data/data/hybrid/ultima_ont_full_cov.samples.tsv config/samples.tsv
        cp .test_data/data/hybrid/ultima_ont_full_cov.units.tsv config/units.tsv
        CMD="dy-r produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    2)
        NAME="Hybrid Ilmn+ONT"
        cp .test_data/data/hybrid/ilmn_ont_full_cov.samples.tsv config/samples.tsv
        cp .test_data/data/hybrid/ilmn_ont_full_cov.units.tsv config/units.tsv
        CMD="dy-r produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    3)
        NAME="ONT only"
        cp .test_data/data/ont/ont_full_cov.samples.tsv config/samples.tsv
        cp .test_data/data/ont/ont_full_cov.units.tsv config/units.tsv
        CMD="dy-r produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    4)
        NAME="ILMN ONLY"
        cp .test_data/data/ilmn/ilmn_full_cov.samples.tsv config/samples.tsv
        cp .test_data/data/ilmn/ilmn_full_cov.units.tsv config/units.tsv
        CMD="dy-r produce_sentieon_bwa_sort_bam produce_bwa_mem2_sort_bam dedup_doppelmark dedup_sentieon produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    5)
        NAME="PB only"
        cp .test_data/data/pacbio/pacbio_full_cov.samples.tsv config/samples.tsv
        cp .test_data/data/pacbio/pacbio_full_cov.units.tsv config/units.tsv
        CMD="dy-r produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    6)
        NAME="Ultima only"
        cp .test_data/data/ultima/ultima_full_cov.samples.tsv config/samples.tsv
        cp .test_data/data/ultima/ultima_full_cov.units.tsv config/units.tsv
        CMD="dy-r produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    *)
        echo "Invalid test number: $TESTNUM (must be 1-6)"
        exit 1
        ;;
esac

echo "============================================================"
echo "TEST $TESTNUM: $NAME"
echo "CMD: $CMD"
echo "============================================================"
eval "$CMD"
RC=$?
echo ""
echo "TEST $TESTNUM RETURN CODE: $RC"
echo "============================================================"
exit $RC

