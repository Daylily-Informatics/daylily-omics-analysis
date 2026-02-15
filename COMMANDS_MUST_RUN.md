headnode=ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175

to clone a new working dir for the floowing tests, use `day-clone -w ssh -t main -d <analysis_description>`, which when done will clone the daylily-omics-analysis repo to `/fsx/analysis_results/ubuntu/<analysis_description>/daylily-omics-analysis/`. You can then cd to that dir, and copy the descrined `<samples.tsv>` and `<units.tsv>` files to `config/` and run the command shown in dry-run mode with `. dyoainit && dy-a slurm hg38 && <command>`

Hybrid Ultima+ONT
samples= .test_data/data/hybrid/ultima_ont_full_cov.samples.tsv
units= .test_data/data/hybrid/ultima_ont_full_cov.units.tsv
command= dy-r produce_sentdhuo_vcf produce_alignstats produce_snv_concordances  -p -j 20 -k  -n

Hybrid Ilmn+ONT
samples= .test_data/data/hybrid/ilmn_ont_full_cov.samples.tsv
units= .test_data/data/hybrid/ilmn_ont_full_cov.units.tsv
command= dy-r produce_sentdhio_vcf produce_alignstats produce_snv_concordances  -p -j 20 -k  -n

ONT only
samples= .test_data/data/ont/ont_full_cov.samples.tsv
units= .test_data/data/ont/ont_full_cov.units.tsv
command= dy-r produce_sentdont_vcf produce_alignstats produce_snv_concordances -p -j 20 -k  -n

ILMN ONLY
samples= .test_data/data/ilmn/ilmn_full_cov.samples.tsv
units= .test_data/data/ilmn/ilmn_full_cov.units.tsv
command= dy-r produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats -p -k -j 20 -n

PB only
samples= .test_data/data/pacbio/pacbio_full_cov.samples.tsv 
units= .test_data/data/pacbio/pacbio_full_cov.units.tsv
command= dy-r produce_sentdpb_vcf produce_alignstats produce_snv_concordances -p -j 20 -k  -n

Ultima only 
samples= .test_data/data/ultima/ultima_full_cov.samples.tsv 
units= .test_data/data/ultima/ultima_full_cov.units.tsv
command= dy-r produce_sentdug_vcf produce_alignstats produce_snv_concordances -p -j 20 -k  -n
