#!/bin/bash
# Check if PacBio alignments exist and what dependencies are missing

echo "=== Check PacBio alignment in test-pb-solo-3x ==="
ls -la /fsx/analysis_results/ubuntu/test-pb-solo-3x/daylily-omics-analysis/results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-PACBIO-REVIO/align/sentmm2/*.cram* 2>/dev/null || echo "No PacBio CRAM found"

echo ""
echo "=== Check if PB_BAM_3X file exists ==="
ls -la /fsx/scratch/downsamples/pacbio/HG003/R0-HG003-D0-0-D0/3p0x/HG003_3p0x.bam 2>/dev/null || echo "File not found"

echo ""
echo "=== Check Roche alignment files ==="
ls -la /fsx/analysis_results/ubuntu/test-roche-solo-3x/daylily-omics-analysis/results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-ROCHE-SBX-DUPLEX/align/roche/*.cram* 2>/dev/null || echo "No Roche CRAM found"

echo ""
echo "=== Check Roche BAM source exists ==="
ls -la /fsx/data/genomic_data/organism_reads/H_sapiens/giab/roche/091025_webinar_data_giab_bam_bwa/HG003.bam 2>/dev/null || echo "Roche BAM not found"

