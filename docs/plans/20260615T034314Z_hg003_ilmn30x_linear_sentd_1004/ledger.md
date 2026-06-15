# HG003 ILMN 30x Linear Sentieon DNAscope 10.0.4 Ledger

Created: 2026-06-15T03:43:14Z

## Objective

Run the same HG003 30x Illumina FASTQs through the linear Sentieon path in DayOA tag `10.0.4`:

- Sentieon BWA alignment: `sent`
- Doppelmark deduplication: `dmd`
- Sentieon DNAscope SNV/indel caller: `sentd`
- Concordance: `produce_snv_concordances`

Report `giabHC` `SNPts`, `SNPtv`, `INS_50`, and `DEL_50` F-score, recall, and precision.

## Gate 0 Inventory

| Check | Evidence |
| --- | --- |
| Requested input data | Same HG003 30x FASTQs used by the pangenome experiment. |
| R1 | `/fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R1.fastq.gz` |
| R2 | `/fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R2.fastq.gz` |
| Sample/truth | HG003; truth root `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/`; `giabHC/HG003.vcf.gz` and `giabHC/HG003.bed` drive the requested ROI. |
| DayOA tag | `10.0.4` |
| Execution contract | DayOA commands run as `ubuntu` in persistent tmux using `source dyoainit`, `dy-a slurm hg38_broad`, and `dy-r`. |
| Planned analysis dir | `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis` |
| Planned tmux session | `hg003_linear_sentd_1004_034314` |
| Linear target config | `aligners=["sent"]`, `dedupers=["dmd"]`, `snv_callers=["sentd"]` |

## Execution Rows

| ID | Scope | Status | Evidence | Terminal Note |
| --- | --- | --- | --- | --- |
| RUN-001 | Create isolated `day-clone -t 10.0.4` analysis directory and copy the HG003 manifests. | DONE | Analysis dir `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis`; tmux `hg003_linear_sentd_1004_034314`; launch marker `__DAYOA_LINEAR_LAUNCH__=hg003_linear_sentd_1004_034314 analysis=hg003_ilmn30x_linear_sentd_1004_20260615T034314Z started=2026-06-15T03:46:10+00:00`. | The first wrapper attempt failed before clone/session creation because `RUN_DIR` was not exported for helper Python; no analysis dir existed, then retry succeeded. |
| RUN-002 | Patch active clone memory for RTG concordance and verify linear Sentieon config. | DONE | Active config patched in `config/day_profiles/slurm/rule_config.yaml`; `rtg_vcfeval.mem_mb=650000`, `rtg_vcfeval.parse_mem_mb=128000`, `rtg_vcfeval.sub_threads=16`, `sentieon_dnascope.mem_mb=350000`; active profile default `config/day_profiles/slurm/config.yaml` set to `mem_mb=100000`; source repo commit `375e5f7` pushed to `origin/jem-dev` with the Slurm template default and test assertion. | Linear config is `aligners=["sent"]`, `dedupers=["dmd"]`, `snv_callers=["sentd"]`; dry-run resolved these exact values. |
| RUN-003 | Run `produce_sent_align produce_dmd_dedup_cram produce_sentD_vcf produce_snv_concordances` with linear config. | DONE | Initial dry-run marker `__DAYOA_STAGE__=linear_sentd_dryrun_done rc=0 2026-06-15T03:46:45+00:00`; BWA job `5601`, Doppelmark job `5602`, DNAscope job `5603`; original sort/index jobs `5604`, `5605`, `5606` failed/OOM at `--mem=3000`; recovery sort/index job `5607` completed with `--mem=100000`; concat/index job `5608` completed with `--mem=250000`; RTG ROI jobs `5609`-`5614` and parse jobs `5615`-`5620` completed; aggregate/prep job `5621` completed; final marker `__DAYOA_STAGE__=linear_sentd_recovery3_live_done rc=0`. | Final VCF `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.sent.dmd.sentd.snv.sort.vcf.gz`; final report `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv`. |
| REPORT-001 | Extract `giabHC` `SNPts`, `SNPtv`, `INS_50`, and `DEL_50` F-score, recall, and precision. | DONE | Direct rows from `other_reports/giab_concordance_mqc.tsv`, filtered to `ROI=giabHC`, `Aligner=sent`, `Deduper=dmd`, `SNVCaller=sentd`. | See results table below. |

## Results

| VariantClass | Fscore | Recall | Precision |
| --- | ---: | ---: | ---: |
| SNPts | 0.9910894471598813 | 0.9842911828115319 | 0.9979822725987043 |
| SNPtv | 0.9909648632528089 | 0.9842319667393776 | 0.9977905105357114 |
| INS_50 | 0.9930644025495393 | 0.987262950463927 | 0.9989344397938302 |
| DEL_50 | 0.9931872108433257 | 0.9875213041282667 | 0.9989185090589832 |

## Planned Command

```bash
dy-r produce_sent_align produce_dmd_dedup_cram produce_sentD_vcf produce_snv_concordances \
  -p -j 12 -k -T 0 --rerun-triggers mtime \
  --config 'aligners=["sent"]' 'dedupers=["dmd"]' 'snv_callers=["sentd"]'
```
