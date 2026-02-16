headnode=ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175

to clone a new working dir for the floowing tests, use `day-clone -w ssh -t main -d <analysis_description>`, which when done will clone the daylily-omics-analysis repo to `/fsx/analysis_results/ubuntu/<analysis_description>/daylily-omics-analysis/`. You can then cd to that dir, and copy the descrined `<samples.tsv>` and `<units.tsv>` files to `config/` and run the command shown in dry-run mode with `. dyoainit && source bin/day_activate slurm hg38 bin/day_run <command>`

Hybrid Ultima+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= dy-r produce_sentdhuo_vcf produce_alignstats produce_snv_concordances  -p -j 20 -k  -n

Hybrid Ilmn+ONT
samples= .test_data/data/hybrid/
units= .test_data/data/hybrid/
command= dy-r produce_sentdhio_vcf produce_alignstats produce_snv_concordances  -p -j 20 -k  -n

ONT only
samples= .test_data/data/ont/
units= .test_data/data/ont/
command= dy-r produce_sentdont_vcf produce_alignstats produce_snv_concordances -p -j 20 -k  -n

ILMN ONLY
samples= .test_data/data/ilmn/
units= .test_data/data/ilmn/
command= dy-r produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats -p -k -j 20 -n

PB only
samples= .test_data/data/pacbio/
units= .test_data/data/pacbio/
command= dy-r produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k  -n

Ultima only 
samples= .test_data/data/ultima/
units= .test_data/data/ultima/
command= dy-r produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k  -n

Roche only
samples= .test_data/data/roche/
units= .test_data/data/roche/
command= dy-r produce_deep19_r_vcf produce_alignstats produce_snv_concordances -p -j 25 -k -n