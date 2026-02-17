#!/bin/bash
# Start test-ug-solo-3x and show info about fixing hybrid tests
BASE=/fsx/analysis_results/ubuntu

echo "=== Starting test-ug-solo-3x with hg38_broad ==="
sess="test-ug-solo-3x"
dir="$BASE/$sess/daylily-omics-analysis"

# Pull latest code first
cd "$dir"
git pull origin feat/modular-hybrid-workflows

# Create tmux session and start
tmux new-session -d -s "$sess"
tmux send-keys -t "$sess" "cd $dir && cp .test_data/data/stress_tests/ug/hg003/3x/samples.tsv config/ && cp .test_data/data/stress_tests/ug/hg003/3x/units.tsv config/ && source dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1" Enter

echo "Started $sess"

echo ""
echo "=== Check Roche BAM headers ==="
samtools view -H /fsx/data/genomic_data/organism_reads/H_sapiens/giab/roche/091025_webinar_data_giab_bam_bwa/HG003.bam 2>/dev/null | grep "^@SQ" | head -3 | awk '{print $1, $2}'

echo ""
echo "=== Suggested fixes for PB hybrid tests ==="
echo "For PB hybrid tests, add 'produce_sentmm2_align_sort' to the target list:"
echo ""
echo "Example for test-hybrid-cli-ilmn-pb-3x:"
echo "  bin/day_run produce_sentmm2_align_sort produce_sentdhip_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1"
echo ""
echo "Example for test-hybrid-mod-ilmn-pb-3x:"
echo "  bin/day_run produce_sentmm2_align_sort produce_sentdhipm_vcf produce_alignstats produce_snv_concordances -p -k -j 20 -T 1"
echo ""
echo "For Roche hybrid tests, add 'pre_prep_roche_bam' to create the Roche CRAM symlink first"

