sudo yum update -y
sudo yum install -y tmux emacs rclone 
sudo dnf install -y fuse fuse3 fuse-common fuse3-libs fuse3-devel htop glances git apptainer


wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh

bash Miniconda3-latest-Linux-x86_64.sh # Accept all defaults


~/miniconda3/bin/conda init
bash

sudo mkdir /fsx
sudo chmod a+wrx /fsx
sudo chmod a+wrx /fsx/
sudo mkdir /scratch
sudo chmod -R a+wrx /scratch
cd fsx/
mkdir data
mkdir logs
mkdir tmp
mkdir scratch
mkdir resources
mkdir analysis_results
mkdir analysis_results/ubuntu
mkdir resources/environments
mkdir resources/environments/containers
mkdir resources/environments/conda


mkdir resources/environments/conda/ec2-user
mkdir resources/environments/conda/ubunt
mkdir resources/environments/container/ubuntu
mkdir resources/environments/container/
mkdir resources/environments/container/ubuntu
mkdir resources/environments/container/ec2-user

mkdir resources/environments/container/ec2-user/$(hostname)
mkdir resources/environments/container/ubuntu/$(hostname)
mkdir analysis_results/ec2-user

# create rclone.conf

 mkdir -p ~/.config/rclone

emacs ~/.config/rclone/rclone.conf

[somename]
type = s3
provider = AWS
access_key_id = <AK>
secret_access_key = <SAK>
region = us-west-2

tmux new -s mount

cd /fsx/
mkdir data

rclone mount --vfs-cache-mode full lsmc:lsmc-dayoa-omics-analysis-us-west-2/data data

# now detach from the tmux session leaving the mount running w/ 'ctl b + d

# new tmux session for ref build and analysis

tmux new -s ana

# build ref
mkdir -p /fsx/scratch/dragen_ref/hg38_dragen
cd /fsx/scratch/dragen_ref

dragen \
  --build-hash-table true \
  --ht-reference /fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta \
  --output-directory /fsx/scratch/dragen_ref/hg38_dragen/



mkdir hg38_pangenome
cd hg38_pangenome/
wget https://s3.us-east-1.amazonaws.com/webdata.illumina.com/downloads/software/dragen/references/genome-files/hg38-alt_masked.cnv.graph.hla.methyl_cg.rna-11-r5.0-1.tar.gz
tar -xzvf hg38-alt_masked.cnv.graph.hla.methyl_cg.rna-11-r5.0-1.tar.gz 

mkdir -p ~/analysis_results/ec2-user/
cd ~/analysis_results/ec2-user/
mkdir hg001

emacs ./dragen_ss.csv
# copy the contents of ./dragen_ss.csv into this file and save

# get your dragen lisc file
## I've stored mine on my local machine in ~/.aws/dragen_creds.rtf

cp $YOURLISCFILE ./dragen_lisc.rtf
export ID=ASTRING=
export PASSWORD=THEO(THERSTRING)


# Run it

mkdir hg001

dragen \
    --fastq-list=./dragen_ss.csv \
    --fastq-list-sample-id=HG001 \
    -r  /fsx/scratch/dragen_ref/hg38_dragen/ \
    --output-directory $PWD/results/hg001 \
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
    --enable-duplicate-marking=true


