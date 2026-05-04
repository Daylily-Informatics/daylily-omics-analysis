# MultiQC QC Targets And Runtime Gating

Daylily exposes staged MultiQC targets so operators can stop at the QC layer
that matches the run scope:

| Target | Scope |
| --- | --- |
| `produce_multiqc_seq_data` | Input sequence-data QC. |
| `produce_multiqc_alignment` | Sequence-data QC plus raw/no-dedup and deduped alignment QC, with optional contamination and relatedness add-ons. |
| `produce_multiqc_variants` | Sequence, alignment, variant QC, annotation summaries, ExpansionHunter, and concordance where truth metadata exists. |
| `produce_multiqc_final` | Alias for the routine final WGS MultiQC report. |
| `produce_multiqc_final_wgs` | Routine final WGS MultiQC report. |

Routine final reporting is controlled by `multiqc_qc` in the active profile
`rule_config.yaml`:

```yaml
multiqc_qc:
    enable_long_running: false
    enable_tools: []
    disable_tools: []
    include_no_dedup_alignment_qc: true
    runtime_gate_minutes: 45
```

The runtime gate is strict: tools that are expected to exceed 45 minutes in a
smoke run must remain out of routine staged and final targets unless
`multiqc_qc.enable_long_running=true` or the tool is explicitly listed in
`multiqc_qc.enable_tools`. Explicitly enabled tools are required DAG inputs;
missing or malformed outputs should fail instead of being silently skipped.

## Routine By Default

These integrations are wired into staged/final MultiQC when their normal
workflow inputs apply and they are not listed in `multiqc_qc.disable_tools`:

| Tool / integration | Stage | MultiQC input |
| --- | --- | --- |
| FastQC | Sequence QC | per-sample FastQC outputs and completion markers |
| fastp | Sequence QC | per-sample fastp HTML/JSON/log outputs |
| SeqFu | Sequence QC | `other_reports/seqfu_mqc.tsv` |
| Sequence QC output inventory | Sequence QC | `other_reports/sequence_qc_outputs_mqc.tsv` |
| alignstats | Alignment QC | `other_reports/alignstats_combo_mqc.tsv` |
| samtools metrics | Alignment QC | gathered samtools metrics marker and metrics files |
| Picard metrics | Alignment QC | per-sample Picard alignment QC outputs |
| Qualimap | Alignment QC | per-sample Qualimap outputs |
| mosdepth | Alignment QC | per-sample mosdepth summaries |
| coverage evenness | Alignment QC | `other_reports/normcovevenness_combo_mqc.tsv` and per-sample markdown |
| Alignment QC output inventory | Alignment QC | `other_reports/alignment_qc_outputs_mqc.tsv` |
| VerifyBamID2 | Contamination QC | per-sample `.vb2.tsv` |
| GATK contamination | Contamination QC | per-sample `.gatk.tsv` |
| bcftools stats | Variant QC | `other_reports/bcftools_variant_stats_mqc.tsv` |
| RTG vcfstats | Variant QC | `other_reports/rtg_vcfstats_mqc.tsv` |
| ExpansionHunter | STR QC | `other_reports/expansionhunter_mqc.tsv` when STR-capable aligners are selected |
| RTG concordance | Benchmarking | `other_reports/giab_concordance_mqc.tsv` when truth metadata is configured |
| Daylily benchmarks | Runtime/cost QC | `other_reports/rules_benchmark_data_mqc.tsv` |

`include_no_dedup_alignment_qc: true` adds the `na` no-dedup passthrough to
alignment QC beside configured real dedupers. Set it to `false` when a dry-run
or smoke fixture cannot produce raw/no-dedup alignment QC.

## Optional Or Deep QC

These tools remain available as first-class rules but are excluded from routine
MultiQC by default:

| Tool / integration | Reason | Enable with |
| --- | --- | --- |
| FastV | Microbial/viral k-mer screening can be resource-heavy and depends on external k-mer resources. | `enable_long_running=true` or `enable_tools=["fastv"]` |
| goleft | Indexcov sex-chromosome inference can fail on sparse or non-standard alignments; keep it explicit until validated for the cohort and assay. | `enable_tools=["goleft"]` |
| KAT | K-mer spectra QC is useful for debugging but can be too slow for routine reads-to-VCF service. | `enable_long_running=true` or `enable_tools=["kat"]` |
| Peddy | Pedigree, sex, and heterozygosity checks need VCFs with enough usable sites and are not valid for every sparse or long-read assay output. | `enable_tools=["peddy"]` |
| site_mix | Genotype-free contamination estimation needs enough usable sites after depth filters and is not valid for every assay depth profile. | `enable_tools=["site_mix"]` |
| Somalier relatedness | Relatedness depends on configured Somalier sites resources and is a cohort-level QC add-on. | `enable_tools=["relatedness"]` |
| VEP | Annotation can exceed the routine QC budget and depends on large external caches. | `enable_long_running=true` or `enable_tools=["vep"]` |
| SnpEff | Annotation can exceed the routine QC budget and depends on large external databases. | `enable_long_running=true` or `enable_tools=["snpeff"]` |

Cluster benchmark validation is still required before promoting any optional
tool to the routine default set. If an optional tool is enabled and cannot
complete, classify the gap in a GitHub issue rather than weakening the DAG.

## Gap Tracking

QC gaps found during the review are tracked as GitHub issues with the prefix
`QC gap:` and labels `qc`, `enhancement`, and `needs-triage`.
