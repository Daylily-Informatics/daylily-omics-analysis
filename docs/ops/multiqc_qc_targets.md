# MultiQC QC Targets And Runtime Gating

Daylily exposes staged MultiQC targets so operators can stop at the QC layer
that matches the run scope:

| Target | Scope |
| --- | --- |
| `produce_multiqc_seq_data` | Input sequence-data QC. |
| `produce_multiqc_alignment` | Sequence-data QC plus raw/no-dedup and deduped alignment QC, contamination, and relatedness. |
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
| SeqFu | Sequence QC | `other_reports/seqfu_mqc.tsv` |
| Sequence QC output inventory | Sequence QC | `other_reports/sequence_qc_outputs_mqc.tsv` |
| alignstats | Alignment QC | `other_reports/alignstats_combo_mqc.tsv` |
| samtools metrics | Alignment QC | gathered samtools metrics marker and metrics files |
| Picard metrics | Alignment QC | per-sample Picard alignment QC outputs |
| Qualimap | Alignment QC | per-sample Qualimap outputs |
| mosdepth | Alignment QC | per-sample mosdepth summaries |
| coverage evenness | Alignment QC | `other_reports/norm_cov_evenness_combo_mqc.tsv` and per-sample markdown |
| goleft | Alignment QC | per-sample goleft outputs |
| Alignment QC output inventory | Alignment QC | `other_reports/alignment_qc_outputs_mqc.tsv` |
| VerifyBamID2 | Contamination QC | panel-scoped per-sample `.vb2.tsv` files |
| VerifyBamID2 panel comparison | Contamination QC | `other_reports/verifybamid2_panel_comparison_mqc.tsv` |
| GATK contamination | Contamination QC | per-sample `.gatk.tsv` |
| site_mix genotype-free contamination | Contamination QC | `other_reports/site_mix_contam_mqc.tsv` and `other_reports/site_mix_donor_mqc.tsv` |
| Contamination output inventory | Contamination QC | `other_reports/contamination_mqc.tsv` |
| Somalier relatedness | Relatedness QC | `other_reports/relatedness_mqc.tsv` |
| bcftools stats | Variant QC | `other_reports/bcftools_variant_stats_mqc.tsv` |
| RTG vcfstats | Variant QC | `other_reports/rtg_vcfstats_mqc.tsv` |
| Peddy | Sample/variant QC | `other_reports/peddy_sample_qc_mqc.tsv` |
| ExpansionHunter | STR QC | `other_reports/expansionhunter_mqc.tsv` when STR-capable aligners are selected |
| Selected HTD callers | HTD QC | `other_reports/htd_calls_mqc.tsv` when `htd_callers` is non-empty |
| RTG concordance | Benchmarking | `other_reports/giab_concordance_mqc.tsv` when truth metadata is configured |
| Daylily benchmarks | Runtime/cost QC | `other_reports/rules_benchmark_data_mqc.tsv` |

`fastp` is intentionally not imported by `workflow/Snakefile` and is not pulled
into any staged/final `produce_multiqc_*` target.

`include_no_dedup_alignment_qc: true` adds the `na` no-dedup passthrough to
alignment QC beside configured real dedupers. Set it to `false` when a dry-run
or smoke fixture cannot produce raw/no-dedup alignment QC.

VerifyBamID2 uses panel-scoped outputs so different SNP panels can be compared
without clobbering each other. The default routine panel is `100k`; run
`produce_verifybamid2_panel_comparison --config verifybamid2_panels=["1k","100k","1m"]`
to compare the historical 1K panel, the 100K 1000G panel, and the staged 1M
panel.
For development or newly generated reference bundles, explicitly override a
panel prefix with `verifybamid2_panel_svd_prefixes={"1m":"/path/to/prefix"}`;
the value must be a real VerifyBamID2 SVD prefix with `.UD`, `.V`, `.mu`, and
`.bed` files.

MultiQC sample names are kept at the deepest meaningful analysis identity:
raw sequence data uses the sample or read-pair ID, alignment QC uses
`sample.aligner`, dedup-level QC uses `sample.aligner.deduper`, variant QC uses
`sample.aligner.deduper.caller`, and chromosome-scattered data keeps the
chromosome explicitly, such as `sample.sent.dmd.sentd.chr1`.

## Optional Or Deep QC

These tools remain available as first-class rules but are excluded from routine
MultiQC by default:

| Tool / integration | Reason | Enable with |
| --- | --- | --- |
| FastV | Microbial/viral k-mer screening can be resource-heavy and depends on external k-mer resources. | `enable_long_running=true` or `enable_tools=["fastv"]` |
| KAT | K-mer spectra QC is useful for debugging but can be too slow for routine reads-to-VCF service. | `enable_long_running=true` or `enable_tools=["kat"]` |
| VEP | Annotation can exceed the routine QC budget and depends on large external caches. | `enable_long_running=true` or `enable_tools=["vep"]` |
| SnpEff | Annotation can exceed the routine QC budget and depends on large external databases. | `enable_long_running=true` or `enable_tools=["snpeff"]` |

site_mix was promoted to routine default after at-sanity validation showed the
GATK pileup plus estimator path completed under the 30-minute service
threshold. If an optional tool is enabled and cannot complete, classify the gap
in a GitHub issue rather than weakening the DAG.

## Gap Tracking

QC gaps found during the review are tracked as GitHub issues with the prefix
`QC gap:` and labels `qc`, `enhancement`, and `needs-triage`.
