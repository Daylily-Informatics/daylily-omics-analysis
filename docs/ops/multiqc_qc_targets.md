# MultiQC QC Targets And Runtime Gating

Daylily exposes staged MultiQC targets so operators can stop at the QC layer
that matches the run scope:

| Target | Scope |
| --- | --- |
| `produce_multiqc_input_data` | Input sequence-data QC. |
| `produce_multiqc_cram` | CRAM/alignment QC, including configured dedup-level alignment QC. |
| `produce_multiqc_snv` | SNV QC summaries and related staged variant metrics. |
| `produce_multiqc_sv` | SV QC/report scope for selected SV callers. |
| `produce_multiqc_sample_qc` | Sample-level QC such as contamination, relatedness, and sex/QC signals. |
| `produce_multiqc_variant_annotation` | Annotation QC such as VEP summaries. |
| `produce_multiqc_all` | Canonical final routine WGS MultiQC report. |

Deprecated compatibility targets remain available for existing runbooks:
`produce_multiqc_seq_data`, `produce_multiqc_alignment`,
`produce_multiqc_variants`, `produce_multiqc_final`, and
`produce_multiqc_final_wgs`.

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

## Stage-Scoped Sample Identity

Final and staged WGS MultiQC reports do not scan `results/day/<build>/`
directly. Each report first builds a deterministic
`results/day/<build>/reports/multiqc_inputs/<stage>/` tree and
`manifest.tsv`. MultiQC scans only that staged tree, and the manifest records
the expected `Sample`, module, source path, staged path, and stage components.
Duplicate `(module, Sample)` pairs fail during staging so MultiQC cannot
silently overwrite one deduper, caller, or panel with another.

The `Sample` field is a stage-scoped analysis identifier, not just the
biological sample. It is derived from the most processed input used by the
tool:

| Tool input class | `Sample` contract |
| --- | --- |
| FASTQ/read QC | `<sample>.R1`, `<sample>.R2`, or explicit run/lane/sample IDs for demux/run QC |
| BAM/CRAM-derived QC | `<sample>.<aligner>.<deduper>` |
| SNV VCF-derived QC | `<sample>.<aligner>.<deduper>.<snv_caller>` |
| SV VCF-derived QC | `<sample>.<aligner>.<deduper>.<sv_caller>` |
| Benchmark subclasses | the stage ID plus ROI/class suffix, for example `<sample>.<aligner>.<deduper>.<caller>.<class>` |

For multi-input tools, the more processed input wins: VCF identity beats
BAM/CRAM identity, which beats FASTQ/run-metric identity. For example, Peddy
run on two Sentieon DNAscope VCFs for the same biological sample must produce
distinct rows such as `HG001.sent.na.sentd` and `HG001.sent.dmd.sentd`.

Some native MultiQC modules derive sample names from file contents instead of
filenames. Daylily stages report-only copies with corrected sample IDs for
those modules. Peddy CSVs and VerifyBamID `.selfSM` files are rewritten in the
staged tree so the native parsers see the same stage-scoped IDs as the custom
DayOA tables. The source analysis outputs are not modified.

## Routine By Default

These integrations are wired into staged/final MultiQC when their normal
workflow inputs apply and they are not listed in `multiqc_qc.disable_tools`:

| Tool / integration | Stage | MultiQC input |
| --- | --- | --- |
| FastQC | Sequence QC | per-sample FastQC outputs and completion markers |
| SeqFu | Sequence QC | `other_reports/seqfu_mqc.tsv` |
| Input sample libraries | Sequence QC | `other_reports/input_sample_libraries_mqc.tsv` |
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
| Truvari SV concordance | Benchmarking | `other_reports/giab_sv_concordance_mqc.tsv` when `truvari_sv_benchmark.truthsets` is configured |
| Daylily benchmarks | Runtime/cost QC | `other_reports/rules_benchmark_data_mqc.tsv` |

`fastp` is intentionally not imported by `workflow/Snakefile` and is not pulled
into any staged/final `produce_multiqc_*` target.

`include_no_dedup_alignment_qc: true` adds the `na` no-dedup passthrough to
alignment QC beside configured real dedupers. Set it to `false` when a dry-run
or smoke fixture cannot produce raw/no-dedup alignment QC.

BCL Convert metrics are not routine defaults because they require a BCL run
directory and SampleSheet, not the normal post-staging `units.tsv` inputs. With
`--config run_context_file=config/runs.tsv`, BCL Convert writes under
`results/runs/<runid>/bclconvert/`, including
`tables/generated.units.tsv`, `metrics/`, and `multiqc_report.html`. Without a
run context, the existing explicit `bclconvert` config path still writes the
genome-build custom-data TSVs into `results/day/<build>/other_reports/`.
Explicitly require those BCL sections in a staged/final report with:

```bash
dy-r produce_multiqc_all \
  --config 'multiqc_qc={"enable_tools":["bclconvert"]}' \
  -p -j 20 -k
```

See [`../workflows/bclconvert_bootstrap.md`](../workflows/bclconvert_bootstrap.md)
for the exact BCL metric sections and output files.

## Separate Run-Level QC

Run-level QC is intentionally outside the final WGS MultiQC DAG because it
starts from vendor run-folder metrics rather than post-staging sample units.
The focused targets now read `config/runs.tsv` when launched as run analysis.
Mounted run-directory mode uses `RUN_DIR=/fsx/run_dir_mounts/<mount_id>`, while
S3 mode is used only when `SOURCE_S3_URI` is explicitly populated. Run outputs
write under `results/runs/<runid>/run_qc/`:

| Target | Inputs | Outputs |
| --- | --- | --- |
| `produce_illumina_run_qc` | `config/runs.tsv` Illumina row with mounted `RUN_DIR`, or explicit `SOURCE_S3_URI`, `PROFILE`, and `REGION` for S3 mode | InterOp CSVs, CheckQC JSON, `summary.html`, `summary.tsv`, and focused InterOp/CheckQC MultiQC HTML |
| `produce_read_fate_river` | the same Illumina run context plus `other_reports/alignstats_combo_mqc.tsv` | read-fate RIVER HTML, TSV, Markdown, and raw-metric inventory |
| `produce_ont_run_qc` | explicit `run_qc.ont.metrics_path` and optional run URI | ONT HTML/TSV summary |
| `produce_ultima_run_qc` | explicit `run_qc.ultima.metrics_path` and optional run URI | Ultima HTML/TSV summary |
| `produce_run_qc_reports` | all explicit run-level inputs above | all run-level reports |

Illumina S3-mode fetches copy only named metrics files; they do not use
`aws s3 sync`, recursive S3 copies, or FASTQ paths. The AWS profile must be
explicit and must not be `default` when S3 mode is selected. Mounted mode links
or copies only the named metric subset from `RUN_DIR` into the run output tree;
it does not write back into the mounted run directory.

VerifyBamID2 uses panel-scoped outputs so different SNP panels can be compared
without clobbering each other. The native VerifyBamID input staged for MultiQC
uses `<sample>.<aligner>.<deduper>.<panel>` so panel-specific `.selfSM` rows do
not collapse back to the biological sample. The default routine panel is
`100k`; run
`produce_verifybamid2_panel_comparison --config verifybamid2_panels=["1k","100k","1m"]`
to compare the historical 1K panel, the 100K 1000G panel, and the staged 1M
panel.
For development or newly generated reference bundles, explicitly override a
panel prefix with `verifybamid2_panel_svd_prefixes={"1m":"/path/to/prefix"}`;
the value must be a real VerifyBamID2 SVD prefix with `.UD`, `.V`, `.mu`, and
`.bed` files.

Report sections are grouped by the DayOA-active tool categories in
`config/external_tools/multiqc_config.yaml`. Custom-content sections use real
MultiQC `parent_id` / `parent_name` grouping, while native modules use
`report_section_order` so read QC appears before alignment QC, sample/variant
identity checks, variant annotation/benchmarking, and workflow benchmark
sections.

## Optional Or Deep QC

These tools remain available as first-class rules but are excluded from routine
MultiQC by default:

| Tool / integration | Reason | Enable with |
| --- | --- | --- |
| FastV | Microbial/viral k-mer screening can be resource-heavy and depends on external k-mer resources. | `enable_long_running=true` or `enable_tools=["fastv"]` |
| VEP | Annotation can exceed the routine QC budget and depends on large external caches. | `enable_long_running=true` or `enable_tools=["vep"]` |
| Unmapped-read metagenomics | Kraken2 classification depends on an explicit external database and can be expensive. | Standalone `produce_unmapped_metagenomics_quick`, or final staged MultiQC with `enable_tools=["unmapped_metagenomics"]` plus `unmapped_metagenomics.kraken2_db`, `threads`, `mem_mb`, `partition`, and optional `read_limit: all`; optional `memory_mapping: true` is required to add Kraken2 `--memory-mapping` |

site_mix was promoted to routine default after at-sanity validation showed the
GATK pileup plus estimator path completed under the 30-minute service
threshold. If an optional tool is enabled and cannot complete, classify the gap
in a GitHub issue rather than weakening the DAG.

## Gap Tracking

QC gaps found during the review are tracked as GitHub issues with the prefix
`QC gap:` and labels `qc`, `enhancement`, and `needs-triage`.
