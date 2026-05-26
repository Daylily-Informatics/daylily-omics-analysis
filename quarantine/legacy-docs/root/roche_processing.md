https://roche-axelios.gitbook.io/xoos/tutorials/germline-small-variant-calling-workflow-for-sbx-duplex-data

Logo
Search…
⌘
k

Ask

0.80
OVERVIEW
XOOS Analysis Tools
Docker Guide
TUTORIALS
Germline Small Variant Calling Workflow for SBX Duplex Data
Measuring Error Rate for SBX Duplex Data
ANALYSIS TOOLS
Pan-Genome Consensus Caller
Small Variant Caller
REFERENCE
Support
Contributing
Release Notes

Powered by GitBook
Overview
Prerequisites
Downsample BAM File
Call Variants with GATK HaplotypeCaller
Filter Variants
Evaluate Variants
Final Output Files
Was this helpful?





Ask

TUTORIALS
Germline Small Variant Calling Workflow for SBX Duplex Data
Overview
This tutorial reproduces the steps demonstrated in the "Germline Small Variant Calling Workflow for SBX Duplex Data" webinar, covering three key analysis workflows for germline genome sequencing data. Each section builds upon Docker-based tools to ensure reproducible results.

Prerequisites
Docker installed

samtools installed

RTG Tools installed

GATK Docker image broadinstitute/gatk-nightly:2025-08-19-4.6.2.0-17-g2a1f41bf3-NIGHTLY-SNAPSHOT accessible

XOOS Small Variant Caller Docker image accessible

The HG001 BAM downloaded and accessible, data can be downloaded from the dataset titled 091025 Webinar GIAB BAMs Giraffe

Some commands do use Docker, but to keep the commands short and readable the boilerplate for the actual docker run is removed, please see the Docker guide for more information about how to use Docker for data analysis.

Downsample BAM File
The BAM files shared during the webinar are full coverage, but the current pre-trained multi-sample models were trained on HG002-HG007 30x data with HG001 left out for evaluation. Therefore, we will analyze the HG001 BAM. Additionally, when computing coverage, we consider only the concordant duplex bases. We have provided the correct subsampling ratios to achieve 30x for each shared BAM.

Sample
Downsampling Ratio
HG001

0.69

HG002

0.63

HG003

0.69

HG004

0.68

HG005

0.63

HG006

0.68

HG007

0.68

The following samtools command will subsample the HG001 BAM to 30x.


Copy
samtools view \
  -@ ${threads} \
  -s 0.69 \
  --subsample-seed 1234 \
  -b \
  --write-index \
  -o HG001.30x.bam##idx##HG001.30x.bam.bai \
  HG001.bam
Call Variants with GATK HaplotypeCaller
This step performs variant calling using GATK HaplotypeCaller with optimized parameters for duplex sequencing data. The following must be executed using the broadinstitute/gatk-nightly:2025-08-19-4.6.2.0-17-g2a1f41bf3-NIGHTLY-SNAPSHOT version of the GATK Docker image. From our experience, GATK HaplotypeCaller is not able to utilize more than 4 cores, because of this we recommend that in practice HaplotypeCaller is run in parallel on individual chromosomes to improve the turn-around time.


Copy
curl -OL https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.40_GRCh38.p14/GRCh38_major_release_seqs_for_alignment_pipelines/GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz
gzip -d GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz
curl -OL https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.40_GRCh38.p14/GRCh38_major_release_seqs_for_alignment_pipelines/GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.fai

gatk CreateSequenceDictionary -R GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna

gatk HaplotypeCaller \
  -I HG001.30x.bam \
  -R GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna \
  -O HG001.30x.vcf.gz \
  -OVI \
  -bamout HG001.30x.bamout.bam \
  -OBI \
  -A AssemblyComplexity \
  -A TandemRepeat \
  -RF MappingQualityReadFilter \
  --activeregion-alt-multiplier 5 \
  --adaptive-pruning true \
  --enable-dynamic-read-disqualification-for-genotyping true \
  --mapping-quality-threshold-for-genotyping 1 \
  --minimum-mapping-quality 1 \
  --min-base-quality-score 6 \
  --native-pair-hmm-threads 4 \
  --smith-waterman FASTEST_AVAILABLE
Filter Variants
This step runs the Roche Small Variant Caller on the GATK VCF leveraging additional information from the GATK BAM and gnomAD population allele frequency database. Please see the Roche Small Variant Caller Documentation for more detailed information.


Copy
curl -OL https://storage.googleapis.com/gatk-best-practices/somatic-hg38/af-only-gnomad.hg38.vcf.gz
curl -OL https://storage.googleapis.com/gatk-best-practices/somatic-hg38/af-only-gnomad.hg38.vcf.gz.tbi

filter_variants \
  --bam-input HG001.30x.bamout.bam \
  --vcf-input HG001.30x.vcf.gz \
  --pop-af-vcf af-only-gnomad.hg38.vcf.gz \
  --workflow germline \
  --threads ${threads} \
  --genome GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna \
  --model /resources/model-germline-sbxd-multisample-snv.txt.gz /resources/model-germline-sbxd-multisample-indel.txt.gz \
  --vcf-output HG001.30x.filtered.vcf.gz
Evaluate Variants
This step compares the filtered variants against truth data to assess accuracy and performance metrics. We use the vcfeval functionality of the RTG Tools suite, for more information please see the RTG Tools README.


Copy
curl -OL https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/NA12878_HG001/NISTv4.2.1/GRCh38/HG001_GRCh38_1_22_v4.2.1_benchmark.vcf.gz
curl -OL https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/NA12878_HG001/NISTv4.2.1/GRCh38/HG001_GRCh38_1_22_v4.2.1_benchmark.vcf.gz.tbi
curl -OL https://ftp-trace.ncbi.nlm.nih.gov/ReferenceSamples/giab/release/NA12878_HG001/NISTv4.2.1/GRCh38/HG001_GRCh38_1_22_v4.2.1_benchmark.bed

rtg RTG_JAVA_OPTS="-Xmx2G" format -o GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.sdf GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna

rtg RTG_JAVA_OPTS="-Xmx2G" vcfeval \
  --threads ${threads} \
  --template GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.sdf \
  --evaluation-regions HG001_GRCh38_1_22_v4.2.1_benchmark.bed \
  --baseline HG001_GRCh38_1_22_v4.2.1_benchmark.vcf.gz \
  --calls HG001.30x.vcf.gz \
  --decompose \
  --ref-overlap \
  --output HG001-vcfeval
For detailed documentation on the output of vcfeval refer to the RTG Tools documentation. To simply print the F1 scores for SNVs and indels, execute the following.


Copy
zcat HG001-vcfeval/snp_roc.tsv.gz | tail -1 | awk '{ print $8 }'

zcat HG001-vcfeval/non_snp_roc.tsv.gz | tail -1 | awk '{ print $8 }'
Final Output Files
Filename
Description
HG001.30x.filtered.vcf.gz

The VCF produced by the Small Variant Caller, detailed documentation

HG001-vcfeval

The output of RTG Tools vcfeval, detailed documentation

Previous
Docker Guide
Next
Measuring Error Rate for SBX Duplex Data
Last updated 5 months ago

© F. Hoffmann-La Roche Ltd

Germline Small Variant Calling Workflow for SBX Duplex Data | XOOS Analysis Tools