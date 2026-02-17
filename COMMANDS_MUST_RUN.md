headnode=ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175

to clone a new working dir for the following tests, use `day-clone -w ssh -t main -d <analysis_description>`, which when done will clone the daylily-omics-analysis repo to `/fsx/analysis_results/ubuntu/<analysis_description>/daylily-omics-analysis/`. You can then cd to that dir, and copy the described `<samples.tsv>` and `<units.tsv>` files to `config/` and run the command shown in dry-run mode with `source ~/.bashrc && <command>`


# HG003 Test Data samples.tsv and units.tsv files
# single platform 3x coverage 
.test_data/data/stress_tests/{ont,ilmn,pb,ug,roche}/hg003/3x/{samples,units}.tsv

# hybrid 3x cov by 2 platforms
.test_data/data/hybrid/{ilmn_ont,ilmn_pb,ug_ont,ug_pb,roche_ont,roche_pb}/hg003/3x/{samples,units}.tsv

# Single-platform tests

ONT only
copy  .test_data/data/stress_tests/ont/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run  produce_sentdont_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

ILMN ONLY
copy  .test_data/data/stress_tests/ilmn/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats -p -k -j 20 -T 1 -n

PB only
copy  .test_data/data/stress_tests/pb/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run  produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Ultima only 
copy  .test_data/data/stress_tests/ug/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Roche only
copy  .test_data/data/stress_tests/roche/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run  produce_deep19_r_vcf produce_alignstats produce_snv_concordances -p -j 25 -k -T 1 -n



# Hybrid tests

Hybrid CLI Ultima+ONT
copy  .test_data/data/hybrid/ug_ont/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ilmn+ONT
copy  .test_data/data/hybrid/ilmn_ont/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ultima+ONT
copy  .test_data/data/hybrid/ug_ont/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ilmn+ONT
copy  .test_data/data/hybrid/ilmn_ont/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ilmn+PB
copy  .test_data/data/hybrid/ilmn_pb/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhip_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ilmn+PB
copy  .test_data/data/hybrid/ilmn_pb/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhipm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ultima+PB
copy  .test_data/data/hybrid/ug_pb/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhup_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ultima+PB
copy  .test_data/data/hybrid/ug_pb/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhupm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Roche+ONT
**the cli does not support this combination**

Hybrid CLI Roche+PB
**the cli does not support this combination**

Hybrid Mod Roche+ONT
copy  .test_data/data/hybrid/roche_ont/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhrom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Roche+PB
copy  .test_data/data/hybrid/roche_pb/hg003/3x/{samples,units}.tsv files to config/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhrpm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n