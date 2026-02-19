headnode=ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175
create and attach to a tmux session that is named <analysis_description>-datetimewseconds , which will stay open after the job is done or fails
run `bash` `source ~/.bashrc`

then clone a day analysis dir with `day-clone`
use `day-clone -w ssh -t <branch> -d <analysis_description>-<datetimewithsec>`, which when done will clone the daylily-omics-analysis repo to `/fsx/analysis_results/ubuntu/<analysis_description>/daylily-omics-analysis/`. You can then cd to that dir.

 and copy the described `<samples.tsv>` and `<units.tsv>` files to `config/` 

# HG003 Test Data samples.tsv and units.tsv files
# single platform 3x coverage 
.test_data/data/stress_tests/{ont,ilmn,pb,ug,roche}/hg003/3x/{samples,units}.tsv

# hybrid 2 unit tests

## ILLMN+ONT
.test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/{units,samples}.tsv

## ULTIMA+ONT
.test_data/data/agbt_2026/prod/hybrid/ultima_ont_expanded_testfix/{units,samples}.tsv


# Single-platform tests

ONT only
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdont_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdont_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1"` 

ILMN ONLY
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats" "-p -j 20 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats" "-p -j 20 -k -T 1"` 

PB only
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdpb_vcf produce_alignstats produce_snv_concordances" "-p -j 2 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdpb_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1"` 

Ultima only (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdug_vcf produce_alignstats produce_snv_concordances" "-p -j 2 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdug_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1"` 

Roche only
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_deep19_r_vcf produce_alignstats produce_snv_concordances" "-p -j 6 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_deep19_r_vcf produce_alignstats produce_snv_concordances" "-p -j 6 -k -T 1"`



# Hybrid tests

## Ultima+ONT cli and modular
Hybrid CLI Ultima+ONT (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuo_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuo_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" ` 


Hybrid Mod Ultima+ONT (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" ` 

## Ilmn+ONT cli and modular
Hybrid CLI Ilmn+ONT
copy  samples.tsv and units.tsv to config/
dryrun command= ` source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhio_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" "-n"` 
command= `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdhio_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" `

Hybrid Mod Ilmn+ONT
copy  samples.tsv and units.tsv to config/
dryrun command= `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhiom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" "-n"` 
command= `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdhiom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" ` 



# OTHER TESTS DO NOT RUN THESE !!!

Hybrid Mod Ultima+PB (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38_broad &&  bin/day_run produce_sentdhupm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n


Hybrid CLI Ilmn+PB
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhip_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ilmn+PB
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhipm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ultima+PB (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38_broad &&  bin/day_run produce_sentdhup_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n


Hybrid CLI Roche+ONT
**the cli does not support this combination**

Hybrid CLI Roche+PB
**the cli does not support this combination**

Hybrid Mod Roche+ONT
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhrom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Roche+PB
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhrpm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n