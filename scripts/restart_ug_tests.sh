#!/bin/bash
# Restart Ultima-based tests with hg38_broad
BASE=/fsx/analysis_results/ubuntu

# Kill and restart UG tests
for sess in test-ug-solo-3x test-hybrid-cli-ug-ont-3x test-hybrid-mod-ug-ont-3x test-hybrid-cli-ug-pb-3x test-hybrid-mod-ug-pb-3x; do
    echo "Killing $sess..."
    tmux kill-session -t "$sess" 2>/dev/null
    
    # Remove old results
    dir="$BASE/$sess/daylily-omics-analysis"
    rm -rf "$dir/results" "$dir/.snakemake" "$dir/logs" 2>/dev/null
    
    # Pull latest code
    cd "$dir" && git pull origin feat/modular-hybrid-workflows 2>/dev/null
done

echo ""
echo "=== Restarting UG tests with hg38_broad ==="

# test-ug-solo-3x
sess="test-ug-solo-3x"
dir="$BASE/$sess/daylily-omics-analysis"
tmux new-session -d -s "$sess"
tmux send-keys -t "$sess" "cd $dir && cp .test_data/data/stress_tests/ug/hg003/3x/samples.tsv config/ && cp .test_data/data/stress_tests/ug/hg003/3x/units.tsv config/ && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter
echo "Started $sess"

# test-hybrid-cli-ug-ont-3x  
sess="test-hybrid-cli-ug-ont-3x"
dir="$BASE/$sess/daylily-omics-analysis"
tmux new-session -d -s "$sess"
tmux send-keys -t "$sess" "cd $dir && cp .test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv config/ && cp .test_data/data/hybrid/ug_ont/hg003/3x/units.tsv config/ && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter
echo "Started $sess"

# test-hybrid-mod-ug-ont-3x
sess="test-hybrid-mod-ug-ont-3x"
dir="$BASE/$sess/daylily-omics-analysis"
tmux new-session -d -s "$sess"
tmux send-keys -t "$sess" "cd $dir && cp .test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv config/ && cp .test_data/data/hybrid/ug_ont/hg003/3x/units.tsv config/ && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter
echo "Started $sess"

# test-hybrid-cli-ug-pb-3x
sess="test-hybrid-cli-ug-pb-3x"
dir="$BASE/$sess/daylily-omics-analysis"
tmux new-session -d -s "$sess"
tmux send-keys -t "$sess" "cd $dir && cp .test_data/data/hybrid/ug_pb/hg003/3x/samples.tsv config/ && cp .test_data/data/hybrid/ug_pb/hg003/3x/units.tsv config/ && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhup_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter
echo "Started $sess"

# test-hybrid-mod-ug-pb-3x
sess="test-hybrid-mod-ug-pb-3x"
dir="$BASE/$sess/daylily-omics-analysis"
tmux new-session -d -s "$sess"
tmux send-keys -t "$sess" "cd $dir && cp .test_data/data/hybrid/ug_pb/hg003/3x/samples.tsv config/ && cp .test_data/data/hybrid/ug_pb/hg003/3x/units.tsv config/ && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhupm_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter
echo "Started $sess"

echo ""
echo "=== UG tests restarted with hg38_broad ==="
tmux ls 2>/dev/null | grep -E "test-ug|test-hybrid.*ug"

