#!/usr/bin/env bash
# Extract FORMAT:DP from VCF, sampling every 1000th variant, compute stats
set -euo pipefail

VCF30="/fsx/analysis_results/ubuntu/pangenome_sr_dryrun_20260221/daylily-omics-analysis/results/day/hg38_broad/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz"
VCF3="/fsx/analysis_results/ubuntu/pangenome_sr_dryrun_20260221/daylily-omics-analysis/results/day/hg38_broad/R3x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/R3x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz"

for label_vcf in "R30x:$VCF30" "R3x:$VCF3"; do
    label="${label_vcf%%:*}"
    vcf="${label_vcf#*:}"
    echo "=== $label ==="
    # FORMAT field order from header: GT:AD:DP:GQ:...  → DP is field 3
    zcat "$vcf" | grep -v '^#' | awk -F'\t' 'NR%1000==0 {
        n=split($9,fmt,":");
        for(i=1;i<=n;i++) if(fmt[i]=="DP") {dp_idx=i; break}
        split($10,vals,":");
        print vals[dp_idx]
    }' | sort -n | awk '
    {vals[NR]=$1; s+=$1}
    END {
        n=NR;
        printf "  sites_sampled: %d\n", n;
        printf "  mean_DP:       %.1f\n", s/n;
        printf "  median_DP:     %d\n", vals[int(n/2+0.5)];
        printf "  p10_DP:        %d\n", vals[int(n*0.1+0.5)];
        printf "  p25_DP:        %d\n", vals[int(n*0.25+0.5)];
        printf "  p75_DP:        %d\n", vals[int(n*0.75+0.5)];
        printf "  p90_DP:        %d\n", vals[int(n*0.9+0.5)];
    }'
done
echo "=== DONE ==="

