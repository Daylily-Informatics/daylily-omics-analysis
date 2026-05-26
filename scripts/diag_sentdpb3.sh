#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pacbio-solo-2/daylily-omics-analysis"
RESULTS_DIR="$ANALYSIS_DIR/results/day/hg38"

echo "=== 1. rep2 gvcf details ==="
REP2_GVCF="$RESULTS_DIR/R0-HG002-rep2-0-rep2-PCR-FREE-PACBIO-REVIO/align/sentmm2/snv/sentdpb/vcfs/1-24/R0-HG002-rep2-0-rep2-PCR-FREE-PACBIO-REVIO.sentmm2.sentdpb.1-24.snv.gvcf"
if [ -f "$REP2_GVCF" ]; then
    ls -lh "$REP2_GVCF"
    wc -l "$REP2_GVCF"
    echo "Last 5 lines:"
    tail -5 "$REP2_GVCF"
else
    echo "rep2 gvcf NOT FOUND"
fi

echo ""
echo "=== 2. rep2 gvcf.idx ==="
REP2_IDX="$REP2_GVCF.idx"
if [ -f "$REP2_IDX" ]; then
    ls -lh "$REP2_IDX"
else
    echo "rep2 gvcf.idx NOT FOUND"
fi

echo ""
echo "=== 3. rep2 vcf (DNAModelApply output) ==="
REP2_VCF="$RESULTS_DIR/R0-HG002-rep2-0-rep2-PCR-FREE-PACBIO-REVIO/align/sentmm2/snv/sentdpb/vcfs/1-24/R0-HG002-rep2-0-rep2-PCR-FREE-PACBIO-REVIO.sentmm2.sentdpb.1-24.snv.vcf"
if [ -f "$REP2_VCF" ]; then
    ls -lh "$REP2_VCF"
    wc -l "$REP2_VCF"
else
    echo "rep2 vcf NOT FOUND - DNAModelApply did not produce output"
fi

echo ""
echo "=== 4. All sacct jobs from last 2 days ==="
sacct -S 2026-02-12 --format=JobID,JobName%50,State%15,ExitCode,MaxRSS%15,Elapsed,NodeList%20 -n 2>/dev/null | tail -40 || echo "sacct not available"

echo ""
echo "=== 5. Check slurm output files ==="
find "$ANALYSIS_DIR" -name "slurm-*.out" -newer "$ANALYSIS_DIR/Snakefile" 2>/dev/null | head -10 || echo "No slurm output files"
# Also check for .err files
find "$ANALYSIS_DIR" -name "*.err" -newer "$ANALYSIS_DIR/Snakefile" 2>/dev/null | head -10 || echo "No .err files"

echo ""
echo "=== 6. Check slurm log dir ==="
ls -lt "$ANALYSIS_DIR/logs/slurm/" 2>/dev/null | head -10 || echo "No slurm log dir"
ls -lt "$ANALYSIS_DIR/.snakemake/slurm_logs/" 2>/dev/null | head -10 || echo "No .snakemake/slurm_logs dir"

echo ""
echo "=== 7. Find any slurm output for sentdpb ==="
find "$ANALYSIS_DIR" -name "*sentdpb*" -newer "$ANALYSIS_DIR/Snakefile" -not -path "*/snv/*" 2>/dev/null | head -20 || echo "None found"
find /tmp -name "*sentdpb*" 2>/dev/null | head -5 || true

echo ""
echo "=== 8. Check the model bundle path ==="
ls -la /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/DNAscopePacBio2.3.bundle/ 2>/dev/null || echo "Bundle dir not found"

echo ""
echo "=== 9. rep1 gvcf details ==="
REP1_GVCF="$RESULTS_DIR/R0-HG002-rep1-0-rep1-PCR-FREE-PACBIO-REVIO/align/sentmm2/snv/sentdpb/vcfs/1-24/R0-HG002-rep1-0-rep1-PCR-FREE-PACBIO-REVIO.sentmm2.sentdpb.1-24.snv.gvcf"
if [ -f "$REP1_GVCF" ]; then
    ls -lh "$REP1_GVCF"
    wc -l "$REP1_GVCF"
    echo "Last 5 lines:"
    tail -5 "$REP1_GVCF"
    echo ""
    echo "rep1 gvcf.idx:"
    ls -lh "$REP1_GVCF.idx" 2>/dev/null || echo "  NOT FOUND"
    echo "rep1 vcf:"
    ls -lh "${REP1_GVCF%.gvcf}.vcf" 2>/dev/null || echo "  NOT FOUND"
else
    echo "rep1 gvcf NOT FOUND"
fi

echo ""
echo "=== DONE ==="

