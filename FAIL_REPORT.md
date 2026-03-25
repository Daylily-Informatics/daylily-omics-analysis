# IFX-GO Workflow Failure Report
**Date**: 2026-03-25 08:30 UTC  
**Cluster**: inflextion-g24  
**Analysis Dir**: /fsx/analysis_results/ubuntu/ifx_go/

## Current Status
- **4 jobs running** (jobs 1658, 1659, 1661, 1662)
- **Failure marker present**: `daylily.failed_run`
- **No new failure modes** — same two blockers as before

## Blocker 1: Segdup-Caller pysam Region Parsing Bug
**Status**: ACTIVE — blocking all segdup gene calls  
**Affected Genes**: HBA, GBA, CYP2D6, NCF1, SMN1, STRC, CYP11B1  
**Affected Samples**: Both (HIOa-HG003-SR15x-ONT15x-39 and HIOa-HG003-SR20x-ONT15x-46)

### Error Details
```
File "pysam/libchtslib.pyx", line 663, in pysam.libchtslib.HTSFile.parse_region
ValueError: too many values to unpack (expected 2)
```

**Root Cause**: In `genecaller/bam_process.py:403`, the code attempts:
```python
_, _, start, end = self.bamh.parse_region(region=region)
```

But `parse_region()` is returning a different tuple structure than expected. This is likely a pysam version incompatibility or API change.

**Workaround Options**:
1. Downgrade pysam to a compatible version
2. Patch segdup-caller's `bam_process.py` to handle the actual return value
3. Contact Sentieon for a patched segdup-caller version

## Blocker 2: Sentieon License Server Outage
**Status**: UNKNOWN — mito jobs running but not yet producing output  
**Affected Rule**: `sentdhiomr_mito_call`  
**Affected Samples**: Both

**Current Job**: 1662 (SR20x sample) — 21+ minutes elapsed, still running

### Previous Error Pattern
```
Connection refused / License server down
```

## Inventory Summary
- **Total VCF index files (.tbi)**: 48 (all valid)
- **Companion VCF files (.vcf.gz)**: 0 (not produced due to blockers)
- **Variant counts**: Cannot compute (missing VCF data)

## Recommendations
1. **Immediate**: Check segdup-caller GitHub issues for pysam compatibility
2. **Parallel**: Monitor mito job 1662 for license server recovery
3. **If mito succeeds**: Focus on segdup-caller patch/downgrade
4. **If both fail**: May need to pause workflow and investigate infrastructure

## Files
- VCF Inventory: `./vcf_inventory.tsv`
- Snakemake Log: `/fsx/analysis_results/ubuntu/ifx_go/daylily-omics-analysis/.snakemake/log/2026-03-25T*.snakemake.log`
- Rule Logs: `results/day/*/align/ont/na/segdup/sentdhiomr/log/*.log`

