dragen \
    --fastq-list=./dragen_ss.csv \
    --fastq-list-sample-id=HG001 \
    -r  /fsx/scratch/dragen_ref/hg38_dragen/ \
    --output-directory $PWD/results/ \
    --output-file-prefix hg001 \
    --validate-pangenome-reference=false \
    --events-log-file=$PWD/results/dragen_events.csv \
    --enable-metrics-json=true \
    --enable-variant-caller=true \
    --vc-enable-bqd=true \
    --vc-enable-vcf-output=true \
    --vc-emit-ref-confidence=GVCF \
    --vc-enable-mapq-zero-regions=true \
    --vc-ml-enable-recalibration=true \
    --enable-vcf-compression=true \
    --enable-ploidy-estimator=true \
    --sample-sex=auto \
    --enable-map-align=true \
    --enable-map-align-output=true \
    --output-format=CRAM \
    --enable-bam-indexing=true \
    --enable-duplicate-marking=true \
    --lic-credentials $CREDFILE

dragen \
    --fastq-list=./dragen_ss.csv \
    -r  /fsx/scratch/dragen_ref/hg38_dragen/ \
    --output-directory $PWD/results_all/ \
    --validate-pangenome-reference=false \
    --events-log-file=$PWD/results_all/dragen_events.csv \
    --enable-metrics-json=true \
    --enable-variant-caller=true \
    --vc-enable-bqd=true \
    --vc-enable-vcf-output=true \
    --vc-emit-ref-confidence=GVCF \
    --vc-enable-mapq-zero-regions=true \
    --vc-ml-enable-recalibration=true \
    --enable-vcf-compression=true \
    --enable-ploidy-estimator=true \
    --sample-sex=auto \
    --enable-map-align=true \
    --enable-map-align-output=true \
    --output-format=CRAM \
    --enable-bam-indexing=true \
    --enable-duplicate-marking=true \
    --lic-credentials $CREDFILE --fastq-list-all-samples

ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ec2-user@ec2-54-149-228-174.us-west-2.compute.amazonaws.com


for SAMPLE in HG001 HG002 HG003 HG004 HG005 HG006 HG007; do
    mkdir -p "$PWD/results_all/${SAMPLE}"
    dragen \
    --fastq-list=./dragen_ss.csv \
    --fastq-list-sample-id="$SAMPLE" \
    -r /fsx/scratch/dragen_ref/hg38_dragen/ \
    --output-directory="$PWD/results_all/${SAMPLE}" \
    --output-file-prefix="${SAMPLE}" \
    --validate-pangenome-reference=false \
    --events-log-file="$PWD/results_all/${SAMPLE}/dragen_events.csv" \
    --enable-metrics-json=true \
    --enable-variant-caller=true \
    --vc-enable-bqd=true \
    --vc-enable-vcf-output=true \
    --vc-emit-ref-confidence=GVCF \
    --vc-enable-mapq-zero-regions=true \
    --vc-ml-enable-recalibration=true \
    --enable-vcf-compression=true \
    --enable-ploidy-estimator=true \
    --sample-sex=auto \
    --enable-map-align=true \
    --enable-map-align-output=true \
    --output-format=CRAM \
    --enable-bam-indexing=true \
    --enable-duplicate-marking=true \
    --lic-credentials  ./dragen.cfg
done




dragen.lisc file in format
```
credentials-1=YOURSTRING
credentials-2=YOURSTRING
```

# NEW COMMAND
SAMPLE="HG002"
mkdir -p $PWD/results_all/${SAMPLE}/
mkdir -p $PWD/results_all/${SAMPLE}/tmp/

dragen \
--ref-dir=/fsx/scratch/dragen_ref/hg38_pangenome/ \
--fastq-list=./dragen_ss.csv \
--fastq-list-sample-id="$SAMPLE" \
--validate-pangenome-reference=true \
--intermediate-results-dir=$PWD/results_all/${SAMPLE}/tmp/ \
--output-directory="$PWD/results_all/${SAMPLE}" \
--output-file-prefix="${SAMPLE}" \
--enable-map-align=true \
--enable-map-align-output=true \
--enable-sort=true \
--enable-duplicate-marking=true \
--enable-variant-caller=true \
--enable-variant-annotation=false \
--enable-sv=true \
--enable-cnv=true \
--cnv-enable-self-normalization=true \
--enable-hla=false \
--enable-targeted=true \
--enable-star-allele=false \
--enable-pgx=false \
--repeat-genotype-enable=true \
--enable-mrjd=true \
--mrjd-enable-high-sensitivity-mode=true \
--enable-telemetry=false \
--enable-personalization=true \
--lic-credentials=./dragen.lisc

For the following Fastqs:::
# These fastqs are all 30x pairs
 ls /fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/
downsampled            HG002_30x_R2.fastq.gz  HG004_30x_R2.fastq.gz  HG006_30x_R2.fastq.gz  NA24143_R2.fastq.gz  NA24385_R2.fastq.gz  NA24694_R2.fastq.gz
HG001_30x_R1.fastq.gz  HG003_30x_R1.fastq.gz  HG005_30x_R1.fastq.gz  HG007_30x_R1.fastq.gz  NA24149_R1.fastq.gz  NA24631_R1.fastq.gz  NA24695_R1.fastq.gz
HG001_30x_R2.fastq.gz  HG003_30x_R2.fastq.gz  HG005_30x_R2.fastq.gz  HG007_30x_R2.fastq.gz  NA24149_R2.fastq.gz  NA24631_R2.fastq.gz  NA24695_R2.fastq.gz
HG002_30x_R1.fastq.gz  HG004_30x_R1.fastq.gz  HG006_30x_R1.fastq.gz  NA24143_R1.fastq.gz    NA24385_R1.fastq.gz  NA24694_R1.fastq.gz

#These fastqs are all downsampled to 5x, 10x, 15x, and 20x
ls /fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/*
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_5x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_5x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_5x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_5x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_5x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_5x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_10x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_10x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_15x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_15x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_20x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_20x_R2.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_5x_R1.fastq.gz
/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_5x_R2.fastq.gz



SAMPLE=$PARSED_SAMPLE
coverage=$PARSED_COV
outdir= $PWD/results_all/${SAMPLE}_${coverage}/
tmpdir=$outdir/tmp/
mkdir -p $outdir
mkdir -p $tmpdir

dragen \
--ref-dir=/fsx/scratch/dragen_ref/hg38_pangenome/ \
--fastq-list=./dragen_ss.csv \
--fastq-list-sample-id="${SAMPLE}_$coverage" \
--validate-pangenome-reference=true \
--intermediate-results-dir=$tmpdir \
--output-directory="$outdir" \
--output-file-prefix="${SAMPLE}_$coveraqe" \
--enable-map-align=true \
--enable-map-align-output=true \
--enable-sort=true \
--enable-duplicate-marking=true \
--enable-variant-caller=true \
--enable-variant-annotation=false \
--enable-sv=false \
--enable-cnv=false \
--cnv-enable-self-normalization=true \
--enable-hla=false \
--enable-targeted=true \
--enable-star-allele=false \
--enable-pgx=false \
--repeat-genotype-enable=true \
--enable-mrjd=true \
--mrjd-enable-high-sensitivity-mode=true \
--enable-telemetry=false \
--enable-personalization=true \
--lic-credentials=./dragen.lisc



RGID,RGSM,RGLB,Lane,Read1File,Read2File
FlowCell123,HG001_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_5x_R2.fastq.gz
FlowCell123,HG001_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_10x_R2.fastq.gz
FlowCell123,HG001_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_15x_R2.fastq.gz
FlowCell123,HG001_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG001_20x_R2.fastq.gz
FlowCell123,HG002_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_5x_R2.fastq.gz
FlowCell123,HG002_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_10x_R2.fastq.gz
FlowCell123,HG002_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_15x_R2.fastq.gz
FlowCell123,HG002_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG002_20x_R2.fastq.gz
FlowCell123,HG003_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_5x_R2.fastq.gz
FlowCell123,HG003_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_10x_R2.fastq.gz
FlowCell123,HG003_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_15x_R2.fastq.gz
FlowCell123,HG003_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG003_20x_R2.fastq.gz
FlowCell123,HG004_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_5x_R2.fastq.gz
FlowCell123,HG004_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_10x_R2.fastq.gz
FlowCell123,HG004_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_15x_R2.fastq.gz
FlowCell123,HG004_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG004_20x_R2.fastq.gz
FlowCell123,HG005_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_5x_R2.fastq.gz
FlowCell123,HG005_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_10x_R2.fastq.gz
FlowCell123,HG005_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_15x_R2.fastq.gz
FlowCell123,HG005_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG005_20x_R2.fastq.gz
FlowCell123,HG006_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_5x_R2.fastq.gz
FlowCell123,HG006_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_10x_R2.fastq.gz
FlowCell123,HG006_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_15x_R2.fastq.gz
FlowCell123,HG006_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG006_20x_R2.fastq.gz
FlowCell123,HG007_5x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_5x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_5x_R2.fastq.gz
FlowCell123,HG007_10x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_10x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_10x_R2.fastq.gz
FlowCell123,HG007_15x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_15x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_15x_R2.fastq.gz
FlowCell123,HG007_20x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_20x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/downsampled/HG007_20x_R2.fastq.gz
FlowCell123,HG001_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG001_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG001_30x_R2.fastq.gz
FlowCell123,HG002_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG002_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG002_30x_R2.fastq.gz
FlowCell123,HG003_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R2.fastq.gz
FlowCell123,HG004_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG004_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG004_30x_R2.fastq.gz
FlowCell123,HG005_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG005_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG005_30x_R2.fastq.gz
FlowCell123,HG006_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG006_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG006_30x_R2.fastq.gz
FlowCell123,HG007_30x,Library1,Lane1,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG007_30x_R1.fastq.gz,/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG007_30x_R2.fastq.gz



#!/bin/bash

set -euo pipefail

INPUT_CSV="dragen_ss.csv"

# Skip header, then read each line
tail -n +2 "$INPUT_CSV" | while IFS=',' read -r RGID RGSM RGLB LANE READ1 READ2; do

    # Parse sample ID and coverage
    SAMPLE="${RGSM%%_*}"      # e.g., HG001
    COVERAGE="${RGSM#*_}"     # e.g., 5x or 30x

    # Setup output paths
    OUTDIR="$PWD/results_all/${SAMPLE}_${COVERAGE}"
    TMPDIR="$OUTDIR/tmp"

    mkdir -p "$OUTDIR"
    mkdir -p "$TMPDIR"

    echo "Running DRAGEN for ${SAMPLE}_${COVERAGE}..."

    dragen \
        --ref-dir=/fsx/scratch/dragen_ref/hg38_pangenome/ \
        --fastq-list=./dragen_ss.csv \
        --fastq-list-sample-id="${SAMPLE}_${COVERAGE}" \
        --validate-pangenome-reference=true \
        --intermediate-results-dir="$TMPDIR" \
        --output-directory="$OUTDIR" \
        --output-file-prefix="${SAMPLE}_${COVERAGE}" \
        --enable-map-align=true \
        --enable-map-align-output=true \
        --enable-sort=true \
        --enable-duplicate-marking=true \
        --enable-variant-caller=true \
        --enable-variant-annotation=false \
        --enable-sv=false \
        --enable-cnv=false \
        --cnv-enable-self-normalization=true \
        --enable-hla=false \
        --enable-targeted=true \
        --enable-star-allele=false \
        --enable-pgx=false \
        --repeat-genotype-enable=true \
        --enable-mrjd=true \
        --mrjd-enable-high-sensitivity-mode=true \
        --enable-telemetry=false \
        --enable-personalization=true \
        --lic-credentials=./dragen.lisc

    echo "Completed: ${SAMPLE}_${COVERAGE}"

done
