exec &> run.log
set -euo pipefail
# Input
input_bam=raw.sort.bam
sample=sample_name

# References used by this script can be obtained from google cloud
# gsutil -m cp gs://broad-references/hg38/v0/chrM/* ./

mt_fasta=Homo_sapiens_assembly38.chrM.fasta
mt_shifted_fasta=Homo_sapiens_assembly38.chrM.shifted_by_8000_bases.fasta
shift_back_chain=ShiftBack.chain
blacklist_sites=blacklist_sites.hg38.chrM.bed

# Binaries
release="/home/release/sentieon-genomics-202112.05"
samtools="/home/release/other_tools/samtools-1.9/samtools"
bcftools='/home/zhipan/projects/bcftools-1.9/bcftools'
picard="java -Xmx6g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=$PWD -jar /home/haodong.chen/bin/picard.jar"

# Step 1 SubsetBamToChrM 
$samtools view -F 0x4 -F 0x8 -h $input_bam chrM | \
  awk '$0~/^@/ || $7 == "=" {print}' | \
  $samtools collate -O -f - tmp_$$ | \
  $samtools fastq -N -1 $sample.chrM.R1.fastq.gz -2 $sample.chrM.R2.fastq.gz -

# Step 2 AlignToMt and AlignToShiftedMt
function AlignAndCall(){
    fq1=$1
    fq2=$2
    sample=$3
    ref=$4
    interval=$5
    output_prefix=$6
    nt=4
    $release/bin/sentieon bwa mem -R "@RG\tID:$sample\tSM:$sample\tPL:Illumina" -K 100000000 -v 3 -t $nt -Y $ref $fq1 $fq2 | \
    $release/bin/sentieon util sort -t $nt -i - --sam2bam -o $output_prefix.sorted.bam
    $release/bin/sentieon driver -t $nt \
        -i $output_prefix.sorted.bam \
        --algo LocusCollector \
        --fun score_info \
        $output_prefix.score.txt
    $release/bin/sentieon driver -t $nt \
        -i $output_prefix.sorted.bam \
        --algo Dedup \
        --score_info $output_prefix.score.txt \
        --metrics $output_prefix.dedup_metrics.txt \
        $output_prefix.deduped.bam
    $release/bin/sentieon driver -t $nt \
        -i $output_prefix.deduped.bam \
        -r $ref \
        --interval $interval \
        --algo TNscope \
        --tumor_sample $sample \
        --min_tumor_allele_frac 0.005 \
        --prune_factor 20 \
        --disable_detector sv \
        --resample_depth 100000 \
        $output_prefix.raw.tnscope.vcf.gz
}
AlignAndCall $sample.chrM.R1.fastq.gz $sample.chrM.R2.fastq.gz $sample $mt_fasta "chrM:576-16024" $sample.MT  &
AlignAndCall $sample.chrM.R1.fastq.gz $sample.chrM.R2.fastq.gz $sample $mt_shifted_fasta "chrM:8025-9144" $sample.ShiftedMT &
wait

# Step 3 LiftoverAndCombineVcfs
$picard LiftoverVcf \
    I=$sample.ShiftedMT.raw.tnscope.vcf.gz \
    O=$sample.ShiftedMT.shifted_back.tnscope.vcf.gz \
    R=$mt_fasta \
    CHAIN=$shift_back_chain \
    REJECT=$sample.ShiftedMT.tnscope.rejected.vcf

$picard MergeVcfs \
    I=$sample.ShiftedMT.shifted_back.tnscope.vcf.gz \
    I=$sample.MT.raw.tnscope.vcf.gz \
    O=$sample.all.tnscope.vcf.gz

# Step 4 Remove variants in blacklist and annotate strand bias
$bcftools view -T ^$blacklist_sites $sample.all.tnscope.vcf.gz | \
    $bcftools filter -s"Strand_bias" -e "INFO/SOR>=10" | \
    $release/bin/sentieon util vcfconvert - $sample.final.tnscope.vcf.gz