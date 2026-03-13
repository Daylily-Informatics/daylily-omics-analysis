#!/bin/bash
# Restart PacBio hybrid tests with sentmm2 alignment target added
BASE=/fsx/analysis_results/ubuntu

restart_pb_test() {
    local sess=$1
    local manifest_dir=$2
    local hybrid_target=$3
    local genome=${4:-hg38}
    
    local dir="$BASE/$sess/daylily-omics-analysis"
    
    echo "=== Restarting $sess ==="
    
    # Kill existing session
    tmux kill-session -t "$sess" 2>/dev/null
    
    # Clean up and pull
    cd "$dir"
    rm -rf results .snakemake logs 2>/dev/null
    git pull origin feat/modular-hybrid-workflows
    
    # Start new session with produce_sentmm2_align_sort BEFORE the hybrid target
    tmux new-session -d -s "$sess"
    tmux send-keys -t "$sess" "cd $dir && cp $manifest_dir/samples.tsv config/ && cp $manifest_dir/units.tsv config/ && source dyoainit && source bin/day_activate slurm $genome && bin/day_run produce_sentmm2_align_sort $hybrid_target produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter
    
    echo "Started $sess with produce_sentmm2_align_sort + $hybrid_target"
}

# Restart all 4 PacBio hybrid tests
restart_pb_test "test-hybrid-cli-ilmn-pb-3x" ".test_data/data/hybrid/ilmn_pb/hg003/3x" "produce_sentdhip_vcf" "hg38"
restart_pb_test "test-hybrid-mod-ilmn-pb-3x" ".test_data/data/hybrid/ilmn_pb/hg003/3x" "produce_sentdhipm_vcf" "hg38"
restart_pb_test "test-hybrid-cli-ug-pb-3x" ".test_data/data/hybrid/ug_pb/hg003/3x" "produce_sentdhup_vcf" "hg38_broad"
restart_pb_test "test-hybrid-mod-ug-pb-3x" ".test_data/data/hybrid/ug_pb/hg003/3x" "produce_sentdhupm_vcf" "hg38_broad"

echo ""
echo "=== All PacBio hybrid tests restarted ==="
tmux ls 2>/dev/null | grep -E "test-hybrid.*pb"

