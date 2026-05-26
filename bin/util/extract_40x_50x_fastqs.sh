#!/bin/bash
# Extract 40x and 50x FASTQs from aligned CRAMs for HG003
# Submit as Slurm jobs on the headnode

set -euo pipefail

OUTPUT_DIR="/fsx/scratch/downsamples/ilmn/HG003"
REF="/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta"

mkdir -p "$OUTPUT_DIR"

# 40x CRAM
CRAM_40X="/fsx/analysis_results/ubuntu/test-hg003-40x50x/daylily-omics-analysis/results/day/hg38/I40x-HG003-X1-1-D1-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/I40x-HG003-X1-1-D1-PCR-FREE-ILMN-NOVASEQ.sent.dmd.cram"

# 50x CRAM
CRAM_50X="/fsx/analysis_results/ubuntu/test-hg003-40x50x/daylily-omics-analysis/results/day/hg38/I50x-HG003-X1-2-D2-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/I50x-HG003-X1-2-D2-PCR-FREE-ILMN-NOVASEQ.sent.dmd.cram"

# Create output dir and clear old incomplete files
mkdir -p ${OUTPUT_DIR}
rm -f ${OUTPUT_DIR}/HG003_40x_R*.fastq.gz ${OUTPUT_DIR}/HG003_50x_R*.fastq.gz 2>/dev/null || true

# Create extraction scripts to avoid shell escaping issues
cat > /tmp/extract_40x.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM
REF="/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta"
CRAM="/fsx/analysis_results/ubuntu/test-hg003-40x50x/daylily-omics-analysis/results/day/hg38/I40x-HG003-X1-1-D1-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/I40x-HG003-X1-1-D1-PCR-FREE-ILMN-NOVASEQ.sent.dmd.cram"
OUTPUT_DIR="/fsx/scratch/downsamples/ilmn/HG003"
samtools fastq -@ 16 -n \
    -1 ${OUTPUT_DIR}/HG003_40x_R1.fastq.gz \
    -2 ${OUTPUT_DIR}/HG003_40x_R2.fastq.gz \
    --reference $REF \
    $CRAM
echo "Done: 40x extraction at $(date)"
SCRIPT

cat > /tmp/extract_50x.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
source /home/ubuntu/miniconda3/etc/profile.d/conda.sh
conda activate SAM
REF="/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta"
CRAM="/fsx/analysis_results/ubuntu/test-hg003-40x50x/daylily-omics-analysis/results/day/hg38/I50x-HG003-X1-2-D2-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/I50x-HG003-X1-2-D2-PCR-FREE-ILMN-NOVASEQ.sent.dmd.cram"
OUTPUT_DIR="/fsx/scratch/downsamples/ilmn/HG003"
samtools fastq -@ 16 -n \
    -1 ${OUTPUT_DIR}/HG003_50x_R1.fastq.gz \
    -2 ${OUTPUT_DIR}/HG003_50x_R2.fastq.gz \
    --reference $REF \
    $CRAM
echo "Done: 50x extraction at $(date)"
SCRIPT

chmod +x /tmp/extract_40x.sh /tmp/extract_50x.sh

# Submit 40x extraction job
sbatch --job-name=extract_40x --partition=i192mem --cpus-per-task=16 --mem=64G --time=4:00:00 \
    --output=/fsx/scratch/logs/extract_40x_%j.out \
    --error=/fsx/scratch/logs/extract_40x_%j.err \
    /tmp/extract_40x.sh

# Submit 50x extraction job
sbatch --job-name=extract_50x --partition=i192mem --cpus-per-task=16 --mem=64G --time=4:00:00 \
    --output=/fsx/scratch/logs/extract_50x_%j.out \
    --error=/fsx/scratch/logs/extract_50x_%j.err \
    /tmp/extract_50x.sh

echo "Submitted 40x and 50x FASTQ extraction jobs"
echo "Output dir: $OUTPUT_DIR"

