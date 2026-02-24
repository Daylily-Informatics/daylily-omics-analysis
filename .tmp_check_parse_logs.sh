#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
echo '=== Job 6040 stderr (giabHC job 28) ==='
tail -20 $BASEDIR/logs/slurm/parse_vcfeval_summary_roi/parse_vcfeval_summary_roi.HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.28.err 2>/dev/null
echo ''
echo '=== Job 6040 stdout ==='
tail -10 $BASEDIR/slurm-6040.out 2>/dev/null
echo ''
echo '=== Job 6043 stderr (hg38 job 36) ==='
tail -20 $BASEDIR/logs/slurm/parse_vcfeval_summary_roi/parse_vcfeval_summary_roi.HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.36.err 2>/dev/null
echo ''
echo '=== Job 6043 stdout ==='
tail -10 $BASEDIR/slurm-6043.out 2>/dev/null
echo ''
echo '=== Parse log for giabHC ==='
tail -10 $BASEDIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/concordance/logs/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.sentdhiomr.giabHC.parse_vcfeval_summary.log 2>/dev/null
echo ''
echo '=== Parse log for hg38 ==='
tail -10 $BASEDIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/concordance/logs/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.sentdhiomr.hg38.parse_vcfeval_summary.log 2>/dev/null
"

