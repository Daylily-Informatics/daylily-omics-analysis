headnode=ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175

to clone a new working dir for the following tests, use `day-clone -w ssh -t main -d <analysis_description>`, which when done will clone the daylily-omics-analysis repo to `/fsx/analysis_results/ubuntu/<analysis_description>/daylily-omics-analysis/`. You can then cd to that dir, and copy the described `<samples.tsv>` and `<units.tsv>` files to `config/` and run the command shown in dry-run mode with `source ~/.bashrc && <command>`

Hybrid Ultima+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances  -p -j 20 -k -T 1  -n

Hybrid Ilmn+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhio_vcf produce_alignstats produce_snv_concordances  -p -j 20 -k -T 1 -n

ONT only
samples= .test_data/data/ont/
units= .test_data/data/ont/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run  produce_sentdont_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

ILMN ONLY
samples= .test_data/data/ilmn/
units= .test_data/data/ilmn/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats -p -k -j 20 -T 1 -n

PB only
samples= .test_data/data/pacbio/
units= .test_data/data/pacbio/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run  produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Ultima only 
samples= .test_data/data/ultima/
units= .test_data/data/ultima/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Roche only
samples= .test_data/data/roche/
units= .test_data/data/roche/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run  produce_deep19_r_vcf produce_alignstats produce_snv_concordances -p -j 25 -k -T 1 -n


Hybrid CLI Ultima+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ilmn+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhio_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ultima+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ilmn+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= source .dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ilmn+PB
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
( bundle /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaPacBio1.1.bundle )
command= source ~/.bashrc && source .dyoainit && source bin/day_activate slurm hg38 && source bin/day_run produce_sentdhip_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ilmn+PB
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
( bundle /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridIlluminaPacBio1.1.bundle )
command= source ~/.bashrc && source .dyoainit && source bin/day_activate slurm hg38 && source bin/day_run produce_sentdhipm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ultima+PB
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
( bundle /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridUltimaPacBio1.0.bundle )
command= source ~/.bashrc && source .dyoainit && source bin/day_activate slurm hg38 && source bin/day_run produce_sentdhup_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ultima+PB
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
( bundle /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridUltimaPacBio1.0.bundle )
command= source ~/.bashrc && source .dyoainit && source bin/day_activate slurm hg38 && source bin/day_run produce_sentdhupm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Roche+ONT (uses sentdhuo config but with Roche data instead of Ultima)
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
( bundle /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/HybridUltimaONT1.1.model.bundle )
command= source ~/.bashrc && source .dyoainit && source bin/day_activate slurm hg38 && source bin/day_run produce_sentdhro_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n
