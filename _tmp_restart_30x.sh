#!/usr/bin/env bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/pangenome_sr_dryrun_20260221/daylily-omics-analysis"
cd "$ANALYSIS_DIR"

# Pull the TMPDIR fix
git pull origin feat/modular-hybrid-workflows

# Clean the failed 30x pangenome output so snakemake will re-run it
rm -f results/day/hg38_broad/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz
rm -f results/day/hg38_broad/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz.tbi
rm -f results/day/hg38_broad/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/pangenome_sr/spmd/snv/sentpg/log/R30x-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.pangenome_sr.spmd.sentpg.log

# Also clean any leftover /dev/shm temp dirs
rm -rf /dev/shm/pangenome_sr_tmp_* 2>/dev/null || true

# Verify /fsx/scratch exists and has space
df -h /fsx/scratch
echo "=== READY FOR RESTART ==="

