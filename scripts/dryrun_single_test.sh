#!/bin/bash
# Dry-run a single test case
# Usage: source dyoainit && dy-a slurm hg38 && source dryrun_single_test.sh <test_num>
# Must be sourced (not executed) so dy-r is available

ADIR="/fsx/analysis_results/ubuntu/dryrun-118/daylily-omics-analysis"
cd "$ADIR"

TESTNUM="${1:?Usage: source $0 <test_num 1-6>}"

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
        return 1 2>/dev/null || exit 1
        ;;
esac

echo "============================================================"
echo "TEST $TESTNUM: $NAME"
echo "CMD: $CMD"
echo "============================================================"
eval "$CMD"
echo "TEST $TESTNUM RETURN CODE: $?"
echo "============================================================"

