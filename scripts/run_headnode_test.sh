#!/bin/bash
# Run a single dry-run test on the headnode
# Usage: TESTNUM=1 bash -l run_headnode_test.sh
# Pass TESTNUM as env var — positional args leak into login profile's dyoainit
#
# dy-a and dy-r are aliases (not functions), so they don't expand in
# non-interactive shells. Call the underlying commands directly:
#   dy-a  → source bin/day_activate
#   dy-r  → bin/day_run

TESTNUM="${TESTNUM:?Set TESTNUM env var (1-6)}"
ADIR="/fsx/analysis_results/ubuntu/dryrun-118/daylily-omics-analysis"
cd "$ADIR" || exit 1

# Activate slurm + hg38 — relax nounset since day_activate uses unguarded $3
set +u
source bin/day_activate slurm hg38
set -u

stage_config() {
    local samples="$1"
    local units="$2"
    cp "$samples" config/samples.tsv
    awk 'NR <= 4' "$units" > config/units.tsv
}

case "$TESTNUM" in
    1)
        NAME="Hybrid Ultima+ONT"
        stage_config .test_data/data/hybrid/ultima_ont_full_cov.samples.tsv .test_data/data/hybrid/ultima_ont_full_cov.units.tsv
        CMD="dy-r produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    2)
        NAME="Hybrid Ilmn+ONT"
        stage_config .test_data/data/hybrid/ilmn_ont_full_cov.samples.tsv .test_data/data/hybrid/ilmn_ont_full_cov.units.tsv
        CMD="dy-r produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    3)
        NAME="ONT only"
        stage_config .test_data/data/ont/ont_full_cov.samples.tsv .test_data/data/ont/ont_full_cov.units.tsv
        CMD="dy-r produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    4)
        NAME="ILMN ONLY"
        stage_config .test_data/data/ilmn/ilmn_full_cov.samples.tsv .test_data/data/ilmn/ilmn_full_cov.units.tsv
        CMD="dy-r produce_sentieon_bwa_sort_bam produce_bwa_mem2_sort_bam dedup_doppelmark dedup_sentieon produce_sentD_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    5)
        NAME="PB only"
        stage_config .test_data/data/pacbio/pacbio_full_cov.samples.tsv .test_data/data/pacbio/pacbio_full_cov.units.tsv
        CMD="dy-r produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -n"
        ;;
    6)
        NAME="Ultima only"
        stage_config .test_data/data/ultima/ultima_full_cov.samples.tsv .test_data/data/ultima/ultima_full_cov.units.tsv
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
# Use bin/day_run directly (the command behind dy-r alias)
eval "${CMD//dy-r/bin/day_run}"
RC=$?
echo ""
echo "TEST_${TESTNUM}_RETURN_CODE: $RC"
echo "============================================================"
exit $RC
