#!/bin/bash
# Start all 15 3x stress tests in tmux sessions
BASE=/fsx/analysis_results/ubuntu

# Kill existing test-* tmux sessions
for s in $(tmux ls 2>/dev/null | grep "^test-" | cut -d: -f1); do
    tmux kill-session -t "$s" 2>/dev/null
done

# Function to start a test
start_test() {
    local name=$1
    local manifest=$2
    local targets=$3
    local jobs=${4:-20}
    local genome=${5:-hg38}

    local dir="$BASE/$name/daylily-omics-analysis"
    echo "Starting $name with genome=$genome..."

    tmux new-session -d -s "$name"
    tmux send-keys -t "$name" "cd $dir && cp $manifest/samples.tsv config/ && cp $manifest/units.tsv config/ && source dyoainit && source bin/day_activate slurm $genome && bin/day_run $targets -p -k -j $jobs -T 1" Enter
}

# 5 Singleton tests
start_test "test-ont-solo-3x" ".test_data/data/stress_tests/ont/hg003/3x" "produce_sentdont_vcf produce_alignstats produce_snv_concordances"
start_test "test-ilmn-solo-3x" ".test_data/data/stress_tests/ilmn/hg003/3x" "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats"
start_test "test-pb-solo-3x" ".test_data/data/stress_tests/pb/hg003/3x" "produce_sentdpb_vcf produce_alignstats produce_snv_concordances"
start_test "test-ug-solo-3x" ".test_data/data/stress_tests/ug/hg003/3x" "produce_sentdug_vcf produce_alignstats produce_snv_concordances" 20 hg38_broad
start_test "test-roche-solo-3x" ".test_data/data/stress_tests/roche/hg003/3x" "produce_deep19_r_vcf produce_alignstats produce_snv_concordances" 25

# 10 Hybrid tests
start_test "test-hybrid-cli-ilmn-ont-3x" ".test_data/data/hybrid/ilmn_ont/hg003/3x" "produce_sentdhio_vcf produce_alignstats produce_snv_concordances"
start_test "test-hybrid-cli-ug-ont-3x" ".test_data/data/hybrid/ug_ont/hg003/3x" "produce_sentdhuo_vcf produce_alignstats produce_snv_concordances" 20 hg38_broad
start_test "test-hybrid-mod-ilmn-ont-3x" ".test_data/data/hybrid/ilmn_ont/hg003/3x" "produce_sentdhiom_vcf produce_alignstats produce_snv_concordances"
start_test "test-hybrid-mod-ug-ont-3x" ".test_data/data/hybrid/ug_ont/hg003/3x" "produce_sentdhuom_vcf produce_alignstats produce_snv_concordances" 20 hg38_broad
start_test "test-hybrid-cli-ilmn-pb-3x" ".test_data/data/hybrid/ilmn_pb/hg003/3x" "produce_sentdhip_vcf produce_alignstats produce_snv_concordances"
start_test "test-hybrid-mod-ilmn-pb-3x" ".test_data/data/hybrid/ilmn_pb/hg003/3x" "produce_sentdhipm_vcf produce_alignstats produce_snv_concordances"
start_test "test-hybrid-cli-ug-pb-3x" ".test_data/data/hybrid/ug_pb/hg003/3x" "produce_sentdhup_vcf produce_alignstats produce_snv_concordances" 20 hg38_broad
start_test "test-hybrid-mod-ug-pb-3x" ".test_data/data/hybrid/ug_pb/hg003/3x" "produce_sentdhupm_vcf produce_alignstats produce_snv_concordances" 20 hg38_broad
start_test "test-hybrid-mod-roche-ont-3x" ".test_data/data/hybrid/roche_ont/hg003/3x" "produce_sentdhrom_vcf produce_alignstats produce_snv_concordances"
start_test "test-hybrid-mod-roche-pb-3x" ".test_data/data/hybrid/roche_pb/hg003/3x" "produce_sentdhrpm_vcf produce_alignstats produce_snv_concordances"

echo ""
echo "=== Started $(tmux ls 2>/dev/null | grep -c '^test-') tmux sessions ==="
tmux ls 2>/dev/null | grep "^test-"

