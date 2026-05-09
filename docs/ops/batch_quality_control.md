# Per-Sample And Batch QC

Daylily QC is generated during workflow processing and aggregated through staged MultiQC targets. The current staged target policy is documented in [`multiqc_qc_targets.md`](multiqc_qc_targets.md), and the exhaustive code-sourced tool inventory is in [`../catalog_of_tools.md`](../catalog_of_tools.md).

Example MultiQC reports are stored under `results/day/<build>/reports/` for completed worksets.
    
## QC Tools Available
Several tools are intentionally redundant. Routine and optional/deep QC can be switched through `multiqc_qc.enable_tools`, `multiqc_qc.disable_tools`, and `multiqc_qc.enable_long_running`.

### [MultiQC](https://github.com/ewels/MultiQC)
  > A tool to aggregate a large number of informatics QC tools output into a single report.

### [Alignstats](https://github.com/jfarek/alignstats)
  > Exhaustive BAM Alignment stats.
  
### [VerifyBAM2](https://github.com/Griffan/VerifyBamID)
  > Human contamination estimation.
  
### Coverage Eveness Estimation
  > A tool which calculates coverage eveness for each chromosome. Intended for use in flagging sample data which may produce questionable SV results.

### [Picard](https://github.com/broadinstitute/picard)
  > Another BAM statistic producer.
  
### [mosdepth](https://github.com/brentp/mosdepth)
  > Depth of coverage statistics
  
### [FastQC](https://github.com/s-andrews/FastQC)
  > Produces fastq quality metrics.
  
### [Peddy](https://github.com/brentp/peddy)
  > Produces biologic sex predictions and flags mismatches with the given biologic sex. Predicts the sample ethnicity, and produces some other VCF stats.
  
### [Qualimap](http://qualimap.conesalab.org/)
  > A bam stats producer.
    
### [goleft](https://github.com/brentp/goleft)
  > Coverage stats producer.
    
### [bcftools](https://github.com/samtools/bcftools/releases/)
  > VCF stats producer.
    
### [samtools](https://github.com/samtools)
  > A bam file stats producer.
  
### Per-Rule Benchmark Runtime Stats
  > aggregates and reports the snakemake runtime performance stats produced per rule.

### Concordance Metrics
  > Concordance metric table for all samples flagged to produce concordance results given a truth vcf and bed file. 
  
