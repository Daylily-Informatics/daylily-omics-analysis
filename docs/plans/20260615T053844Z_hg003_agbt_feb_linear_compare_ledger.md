# HG003 AGBT February 30x Linear Sentieon Comparison Ledger

Created: 2026-06-15T05:38:44Z

## Objective

Investigate why the June HG003 30x linear Sentieon DNAscope `giabHC` concordance is around `0.99` instead of the expected `0.999+`, by finding an HG003 30x AGBT-era dataset from late February 2026 and running the same linear DayOA comparison:

- Sentieon BWA alignment: `sent`
- Doppelmark deduplication: `dmd`
- Sentieon DNAscope SNV/indel caller: `sentd`
- Concordance: `produce_snv_concordances`

Report whether the AGBT February HG003 30x input reproduces the lower F-scores or returns the expected higher `giabHC` values.

## Gate 0 Inventory

| Check | Evidence |
| --- | --- |
| Repo | `/Users/jmajor/projects/lsmc/daylily-omics-analysis` |
| Branch | `jem-dev` tracking `origin/jem-dev` |
| Existing dirty/untracked state | Pre-existing untracked `docs/plans/20260615T052434Z_altairval_hg003_ultima_*` files and `jem/`; do not alter unless specifically requested. |
| Current comparison source | June linear report `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv` |
| Current linear `giabHC` SNPts/SNPtv | SNPts F-score `0.9910894471598813`; SNPtv F-score `0.9909648632528089` |
| Prior pangenome `giabHC` SNPts/SNPtv | Prior pangenome report `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv`; SNPts F-score `0.9939545440446199`; SNPtv F-score `0.9941639258632771` |
| Execution contract | Any DayOA workflow run must use `day-clone`, a persistent `ubuntu` tmux/login shell, `source dyoainit`, `dy-a slurm hg38_broad`, and `dy-r`; no raw `snakemake`. |

## Execution Rows

| ID | Scope | Status | Evidence | Terminal Note |
| --- | --- | --- | --- | --- |
| FIND-001 | Locate an HG003 30x AGBT-era dataset from late February 2026. | DONE | User pointed to `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre<datetime>`. Pure ILMN 30x hg38 matches found in `FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_20260221_seta/ilmn_hg003_prod/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv` and `FSxLustre20260216T130001Z/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv`. | Both reports contain sample `I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ`; both give identical `sent/sentd` `giabHC` rows. |
| RUN-001 | Create isolated DayOA analysis clone for the selected AGBT HG003 dataset. | SKIPPED | Archived Feb 2026 pure-ILMN hg38 reports already contain the requested `I2-HG003-30x` `giabHC` rows. | No rerun needed to answer this comparison. |
| RUN-002 | Run `sent+dmd+sentd` and `produce_snv_concordances` with raised Slurm memory defaults. | SKIPPED | Archived command for `ilmn_hg003_prod` was `produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats`; legacy report schema lacks a `Deduper` column, but the producing command includes Doppelmark. | No new Slurm jobs submitted. |
| COMP-001 | Compare `giabHC` `SNPts`, `SNPtv`, `INS_50`, and `DEL_50` against June linear and prior pangenome reports. | DONE | Direct filter: sample contains `I2-HG003-30x`; `CmpFootprint=giabHC`; `Aligner=sent`; `SNVCaller=sentd`; legacy `Deduper` absent but command used `dedup_doppelmark`. Compared to June linear report `jem/linear_giab_concordance_mqc.tsv` filtered to `ROI=giabHC`, `Aligner=sent`, `Deduper=dmd`, `SNVCaller=sentd`. | See comparison table below. |
| DIAG-001 | Diagnose what changed: input FASTQ provenance, truth/ROI, model/tool/config, or comparison extraction. | DONE | June FSx FASTQs match canonical S3 multipart ETags for `HG003_30x_R1.fastq.gz` and `HG003_30x_R2.fastq.gz`; the low June scores are not explained by using different 30x FASTQ bytes. Feb archived high-score report is pure ILMN hg38, while the June run compared here is hg38_broad. | Main observed delta is recall/FN, not precision. |
| DIAG-002 | Compare Feb AGBT and June DNAscope command arguments from `.snakemake/log` and runtime `cmdline:` logs. | DONE | Feb `.snakemake/log/2026-02-17T140338.582752.snakemake.log` lines 3669-3725 and runtime `results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/log/vcfs/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ.sent.dmd.sentd.1-24.snv.log` lines 5 and 81. June `.snakemake/log/2026-06-15T034733.224993.snakemake.log` lines 302-347 and runtime `results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/log/vcfs/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.sent.dmd.sentd.1-24.snv.log` lines 2 and 78. | DNAscope model and pop VCF version did not change; the command-level delta is the reference FASTA/genome root, plus wrapper/root path differences. |

## Pure ILMN 30x `giabHC` Comparison

Archived Feb 2026 source rows:

- `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_20260221_seta/ilmn_hg003_prod/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv`
- `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv`

Both archived files give the same direct values for `I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ`.

| VariantClass | Feb 2026 pure ILMN hg38 Fscore | June 2026 linear hg38_broad Fscore | Delta June - Feb | Feb Recall | June Recall | Feb Precision | June Precision | Feb TP | June TP | Feb FP | June FP | Feb FN | June FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SNPts | 0.9968114926574638 | 0.9910894471598813 | -0.005722045497582484 | 0.9957327071739398 | 0.9842911828115319 | 0.9978926182074053 | 0.9979822725987043 | 2244970 | 2219302 | 4741 | 4487 | 9621 | 35419 |
| SNPtv | 0.9964304036166926 | 0.9909648632528089 | -0.005465540363883692 | 0.9951814852560729 | 0.9842319667393776 | 0.9976824606149292 | 0.9977905105357114 | 1066329 | 1055825 | 2477 | 2338 | 5163 | 16915 |
| INS_50 | 0.9977486101113444 | 0.9930644025495393 | -0.004684207561805098 | 0.996747612074053 | 0.987262950463927 | 0.9987516207029471 | 0.9989344397938302 | 228011 | 247493 | 285 | 264 | 744 | 3193 |
| DEL_50 | 0.9979572841763655 | 0.9931872108433257 | -0.004770073333039804 | 0.9971605873057677 | 0.9875213041282667 | 0.9987552551314813 | 0.9989185090589832 | 242318 | 250309 | 302 | 271 | 690 | 3163 |

## FASTQ Provenance Check

The June linear run used:

- `/fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R1.fastq.gz`
- `/fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/HG003_30x_R2.fastq.gz`

Those match the canonical S3 multipart ETags:

- `HG003_30x_R1.fastq.gz`: `51d9cb9c6de8fba4fe669d12155caffb-2841`
- `HG003_30x_R2.fastq.gz`: `c46c9a64a16cb90b1feba8c33b1ac22e-2938`

## DNAscope Command Comparison

Evidence sources:

- Feb AGBT Snakemake log: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_20260221_seta/ilmn_hg003_prod/daylily-omics-analysis/.snakemake/log/2026-02-17T140338.582752.snakemake.log`
- Feb AGBT runtime log: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260216T130001Z/analysis_results/ubuntu/agbt_20260221_seta/ilmn_hg003_prod/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/log/vcfs/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ.sent.dmd.sentd.1-24.snv.log`
- June Snakemake log: `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis/.snakemake/log/2026-06-15T034733.224993.snakemake.log`
- June runtime log: `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/log/vcfs/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.sent.dmd.sentd.1-24.snv.log`

| Argument | Feb 2026 AGBT pure ILMN hg38 | June 2026 linear hg38_broad | Same? |
| --- | --- | --- | --- |
| Rule | `sent_DNAscope` | `sent_DNAscope` | yes |
| Sample | `I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ` | `R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ` | no, naming/input config differs |
| Input CRAM | `results/day/hg38/.../align/sent/dmd/...sent.dmd.cram` | `results/day/hg38_broad/.../align/sent/dmd/...sent.dmd.cram` | same aligner/deduper shape |
| Threads | `--thread_count 192`; `DNAModelApply -t 192` | `--thread_count 192`; `DNAModelApply -t 192` | yes |
| Intervals | `chr1`-`chr22`,`chrX`,`chrY` | `chr1`-`chr22`,`chrX`,`chrY` | yes |
| Reference FASTA | `/fsx/data/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta` | `/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta` | no |
| DNAscope algo | `--algo DNAscope` | `--algo DNAscope` | yes |
| Population VCF | `/fsx/data/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz` | `/fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz` | same filename/version, different root |
| PCR indel model | `--pcr_indel_model none` | `--pcr_indel_model none` | yes |
| Emit mode | `--emit_mode variant` | `--emit_mode variant` | yes |
| DNAscope model | `/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaWGS2.2.bundle/dnascope.model` | `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaWGS2.2.bundle/dnascope.model` | same bundle/model, different root |
| DNAModelApply model | `SentieonIlluminaWGS2.2.bundle/dnascope.model` | `SentieonIlluminaWGS2.2.bundle/dnascope.model` | yes |
| Sentieon driver | `/fsx/data/cached_envs/sentieon-genomics-202503.02/libexec/driver` in runtime log | `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/libexec/driver` in runtime log | same Sentieon release path name, different asset root |
| Instance type | `m7i.48xlarge` | `c8id.metal-96xl` | no |
| Rule resources | `mem_mb=200000`, `time=5440`, partitions `i192,i192mem,i192bigmem` | `mem_mb=200000`, `time=200`, partitions `i384nvme,i192nvme` | partially |

Interpretation:

- The June linear run did not use a newer DNAscope model than the Feb AGBT pure-ILMN hg38 run. Both used `SentieonIlluminaWGS2.2.bundle/dnascope.model`.
- The June linear run did not switch pop VCF version by filename. Both used `pop-v20g41-20251216.vcf.gz`.
- The largest command-level difference in the SNV-producing call is the reference FASTA and genome root: Feb used `hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta`, while June used `hg38_broad/Homo_sapiens_assembly38.fasta`.
- The lower June `giabHC` score is recall/FN-driven while precision is comparable or slightly higher, so this command comparison points first at the `hg38_broad` reference/truth/ROI coordinate environment rather than a DNAscope model change.

## RTG / Alt-Contig Note

Read-only follow-up on 2026-06-15:

- `/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta.fai` has `195` contigs.
- `/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta.fai` has `3366` contigs.
- The HG003 `giabHC` BED used here is primary autosomes only: `chr1`-`chr22`.
- `bcftools 1.23.1` readback showed the HG003 `giabHC` truth VCF has `4,000,097` actual records, all on `chr1`-`chr22`; the header lists `195` contigs, but there are `0` truth records on non-primary/extra contigs.
- Candidate VCF readback showed `0` non-primary/extra-contig records in either June callset. The `hg38` callset has `5,977,053` records on `chr1`-`chr22`,`chrX`,`chrY`; the `hg38_broad` callset has `5,710,185` records on the same contigs.
- Candidate records overlapping the `giabHC` BED dropped from `4,012,155` in the `hg38` rerun to `3,932,643` in the `hg38_broad` run.
- RTG `giabHC` output VCFs contain only `chr1`-`chr22` records. `hg38`: `tp=3,815,562`, `fp=7,821`, `fn=16,310`. `hg38_broad`: `tp=3,773,220`, `fp=7,363`, `fn=58,695`.
- The `hg38_broad` BWA reference prefix listing showed `.amb`, `.ann`, `.bwt`, `.pac`, `.sa`, `.0123`, `.bwt.2bit.64`, `.r150.sti`, and `.r250.sti`, but no `${reference}.alt` sidecar. The `sentieon bwa mem` command did not pass an explicit ALT-remapping argument; it used the same Sentieon ILMN BWA model as `hg38` and only changed the reference FASTA.
- The June broad `giabHC` `vcfeval.log` command was:
  - `rtg vcfeval --decompose --squash-ploidy --ref-overlap -e /fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/giabHC/HG003.bed -b /fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/giabHC/HG003.vcf.gz -c results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ.sent.dmd.sentd.snv.sort.vcf.gz -o results/day/hg38_broad/R0-HG003-D0-0-D0-PCR-FREE-ILMN-NOVASEQ/align/sent/dmd/snv/sentd/concordance/_giabHC -t /fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.sdf --threads 16`

Interpretation:

- This is consistent with an alt/decoy/reference-context effect, but not specifically evidence that RTG is mishandling alternate contigs.
- RTG is being asked to score primary-coordinate GIAB HC regions/truth against calls produced from the `hg38_broad` alignment/calling context. If reads or equivalent calls move to alt/decoy contigs before vcfeval, primary-contig truth sites can become FNs; `vcfeval` will not infer alternate-contig equivalence from this command.
- The observed `giabHC` drop is therefore upstream of RTG: the broad-reference DNAscope callset contains fewer primary-region candidate variants in the HC BED and RTG reports a large FN increase with slightly fewer FPs. Limiting RTG to `chr1`-`chr22` is a reasonable guardrail but does not explain or fix this delta.

## Pangenome vs hg38 Solo Note

Read-only follow-up on 2026-06-15:

- The June pangenome runs are under `results/day/hg38_broad`, not `results/day/hg38`.
- `PG_CURRENT` report: `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv`.
- `PG_PRIOR` report: `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv`.
- `PG_CURRENT` active `sentieon_pangenome_sr` block uses:
  - `gbz: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/hprc-v2.0-mc-grch38.gbz`
  - `hapl: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/hprc-v2.0-mc-grch38.hapl`
  - `model: /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.2.bundle`
  - `pop_vcf: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20-20260528.vcf.gz`
- `PG_PRIOR` active `sentieon_pangenome_sr` block uses:
  - `gbz: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/hprc-v2.0-mc-grch38.gbz`
  - `hapl: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/hprc-v2.0-mc-grch38.hapl`
  - `model: /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle`
  - `pop_vcf: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz`
- Compared with the June `hg38` solo linear rerun, the pangenome `giabHC` loss is recall/FN-driven and precision-improving:

| Scope | All Fscore | Recall | Precision | FN | TP | FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Linear `hg38` solo `sent+dmd+sentd` | 0.9968477862592428 | 0.9957435947756084 | 0.9979544293626874 | 16310 | 3815562 | 7821 |
| Pangenome current `hg38_broad` `pangenome_sr+spmd+sentpg` | 0.9939747222460159 | 0.9887296472361579 | 0.9992757428449275 | 43187 | 3788725 | 2746 |
| Pangenome prior `hg38_broad` `pangenome_sr+spmd+sentpg` | 0.9942140957701462 | 0.9890532511950947 | 0.9994290810551953 | 41947 | 3789967 | 2165 |

Interpretation:

- The pangenome result is not worse because it is adding many false positives in `giabHC`; it is substantially more precise than linear `hg38` solo.
- The pangenome result is worse because it misses more primary-coordinate truth calls in `giabHC`. Versus linear `hg38` solo, prior pangenome has `+25,637` All-class FNs and `-5,656` FPs; current pangenome has `+26,877` All-class FNs and `-5,075` FPs.
- This points to a conservative pangenome/projection/calling behavior in the `hg38_broad` pangenome context, not RTG counting extra-contig calls.

## Sentieon Pangenome Recommendation Check

Read-only follow-up on 2026-06-15:

- Sentieon's public DNAscope Illumina pangenome material reports 30x benchmark performance around SNP F1 `>99.89%`, indel F1 `>99.78%`, and total error counts below `10000` for supported WGS truth-set benchmarks.
- The June pangenome `giabHC` runs here are not in that range. In All-class `giabHC`, current pangenome has `FN+FP=45933`; prior pangenome has `FN+FP=44112`; linear `hg38` solo has `FN+FP=24131`.
- The pop VCF pairing appears correct by bundle metadata:
  - `SentieonIlluminaPangenomeRealignWGS1.2.bundle` `bundle_info.json` has `SentieonVcfID: population-hprc-v2.0-20260528` and `pangenome: hprc-v2.0-mc-grch38.gbz`.
  - `SentieonIlluminaPangenomeRealignWGS1.0.bundle` `bundle_info.json` has `SentieonVcfID: population-hprc-v2.0+gnomad-v4.1.0-20251216` and `pangenome: hprc-v2.0-mc-grch38.gbz`.
  - The run-local configs paired WGS1.2 with `pop-v20-20260528.vcf.gz` and WGS1.0 with `pop-v20g41-20251216.vcf.gz`.
- Other required pangenome supporting files were present and passed through the run-local command: `hprc-v2.0-mc-grch38.gbz`, `hprc-v2.0-mc-grch38.hapl`, `hg38_canonical.bed`, dbSNP, and `--pcr_free`.
- The run was not an exact match to the current Sentieon CLI recommendation:
  - The June `10.0.4-dirty` pangenome logs used `bin/dayoa_sentieon_cli sentieon-pangenome`, while current Sentieon CLI docs name the pipeline command `dnascope-pangenome`.
  - The June pangenome runs used `-r /fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta`; Sentieon's DNAscope CLI documentation recommends a reference without alternate contigs, or a `.alt` file when alternate contigs are present.
  - The pangenome runtime log reported `[M::bwa_idx_load_from_disk] read 0 ALT contigs` for the broad FASTA context.
  - The June run used the `sentieon-genomics-202503.02` install; current local templates now point WGS1.2 at `sentieon-genomics-202503.03`.

Interpretation:

- The strongest current conclusion is that the low June pangenome result should not be treated as a clean Sentieon-recommended pangenome benchmark.
- The model/pop pairing is probably not the problem; the bundle metadata supports the configured pairings.
- The leading command-level concerns are the `hg38_broad` reference context without ALT-aware sidecar behavior, use of the old `sentieon-pangenome` wrapper name, and the older `202503.02` install relative to current local assets.
- A clean adjudication should rerun current WGS1.2 pangenome with the current CLI path and the `hg38` no-alt reference context, keeping the validated WGS1.2/pop-v20-20260528/GBZ/HAPL pairing.

## Current Pangenome hg38 Rerun

Launch follow-up on 2026-06-15:

- Objective: rerun the current Sentieon ILMN pangenome HG003 30x workflow with the `hg38` active build instead of `hg38_broad`, changing the reference context while keeping the current WGS1.2 pangenome model/pop pairing.
- Tmux session: `hg003_pg_current_hg38_1004_080558`.
- Analysis clone: `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_current_hg38_1004_20260615T080558Z/daylily-omics-analysis`.
- `day-clone` ref: `10.0.4`, detached commit `b0e35b9de7288031c605a480dad35a7225811479`.
- Manifests staged from the prior current pangenome run:
  - `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/daylily-omics-analysis/config/samples.tsv`
  - `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/daylily-omics-analysis/config/units.tsv`
- Slurm template resource patch in the clone: `rtg_vcfeval.mem_mb: 650000`.
- Activation command sequence in the persistent `ubuntu` tmux pane:
  - `source dyoainit`
  - `dy-a slurm hg38`
  - dry-run: `dy-r produce_pangenome_sr_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime -n`
  - live run: `dy-r produce_pangenome_sr_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime`
- Dry-run result: `RETURN CODE: 0`; DAG had `20` jobs, with all pangenome/concordance outputs under `results/day/hg38`.
- Live launch evidence: `ps` showed `/home/ubuntu/miniconda3/envs/DAYOA/bin/python ... snakemake --profile=.../config/day_profiles/slurm produce_pangenome_sr_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime`; first local staging jobs completed under `results/day/hg38`.
- Current WGS1.2 live Slurm job: `5650`, rule `sentieon_pangenome_sr`, `i384nvme`; command emitted with `-r /fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta`, model `SentieonIlluminaPangenomeRealignWGS1.2.bundle`, and pop VCF `pop-v20-20260528.vcf.gz`.

Prior-bundle paired rerun on 2026-06-15:

- Objective: run the same `hg38` no-alt pangenome test with the preceding WGS1.0 bundle and matching prior pop VCF.
- Tmux session: `hg003_pg_prior_hg38_1004_082114`.
- Analysis clone: `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_prior_hg38_1004_20260615T082114Z/daylily-omics-analysis`.
- `day-clone` ref: `10.0.4`, same HG003 30x manifests staged from `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/daylily-omics-analysis/config/`.
- Run-local Slurm template/profile edits:
  - `rtg_vcfeval.mem_mb: 650000`
  - `sentieon_pangenome_sr.model: /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bundles/SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle`
  - `sentieon_pangenome_sr.pop_vcf: /fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz`
- Activation command sequence in the persistent `ubuntu` tmux pane:
  - `source dyoainit`
  - `dy-a slurm hg38`
  - dry-run: `dy-r produce_pangenome_sr_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime -n`
  - live run: `dy-r produce_pangenome_sr_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime`
- Dry-run result: `RETURN CODE: 0`; DAG had `20` jobs, with all pangenome/concordance outputs under `results/day/hg38`.
- Prior WGS1.0 live Slurm job: `5651`, rule `sentieon_pangenome_sr`, `i384nvme`; command emitted with `-r /fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta`, model `SentieonIlluminaPangenomeRealignWGS1.0.bundle/SentieonIlluminaPangenomeRealignWGS1.0.bundle`, and pop VCF `pop-v20g41-20251216.vcf.gz`.

Memory follow-up on 2026-06-15T09:14:22Z:

- User requested minimum memory requests of at least `50000` for RTG and concordance-adjacent rules.
- Patched both active hg38 pangenome analysis clones:
  - `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_current_hg38_1004_20260615T080558Z/daylily-omics-analysis`
  - `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_prior_hg38_1004_20260615T082114Z/daylily-omics-analysis`
- Config edits applied in both `config/day_profiles/slurm/rule_config.yaml` and `config/day_profiles/slurm/templates/rule_config.yaml`:
  - `rtg_vcfeval.mem_mb: 650000`
  - `rtg_vcfeval.parse_mem_mb: 128000`
  - `prep_for_concordance_check.mem_mb: 50000`
  - `run_concordance.mem_mb: 50000`
  - `rtg_vcfstats.mem_mb: 50000`
- Rule-level edits applied in both run-local clones because 10.0.4 had YAML-only gaps:
  - `workflow/rules/rtg_vcfeval.smk`: `prep_for_concordance_check` now declares `mem_mb=config["prep_for_concordance_check"]["mem_mb"]`.
  - `workflow/rules/rtg_vcfstats.smk`: `rtg_vcfstats` now declares `mem_mb=config["rtg_vcfstats"]["mem_mb"]`.
- Caveat: the already-running Snakemake controllers were launched before these edits, so they may not reload the updated resource declarations. If downstream RTG/concordance jobs are submitted with stale low-memory resources, rerun the concordance target from the completed pangenome VCFs using the patched run-local configs.
- Status at this memory edit: Slurm jobs `5650` and `5651` were still running `sentieon_pangenome_sr`; no `results/day/hg38/other_reports/giab_concordance_mqc.tsv` existed yet in either clone.

Altair ROI prefix rename on 2026-06-15T09:55:08Z:

- Renamed the HG003 Altair ROI prefix from dotted `altair-v1.1` to hyphenated `altair-v1-1` in the S3 references bucket.
- Verified before deletion that source and target S3 prefixes each had `3` objects totaling `154338935` bytes.
- Removed the old source prefix:
  - `s3://lsmc-dayoa-references-usw2/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/altair-v1.1/`
- Verified final S3 state:
  - Old `altair-v1.1` prefix: `0` objects, `0` bytes.
  - New `altair-v1-1` prefix: `3` objects, `154338935` bytes.
  - Objects retained under `altair-v1-1`: `HG003.bed`, `HG003.vcf.gz`, `HG003.vcf.gz.tbi`.
- Verified FSx reference root now exposes only `altair-v1-1` for the Altair ROI under:
  - `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/`
- The previous local dotted directory remains only as a scratch backup outside the reference tree:
  - `/fsx/scratch/HG003_altair-v1.1_old_20260615T094019Z`

Status on 2026-06-15T10:09:16Z:

- Current and prior `hg38` pangenome concordance reports were complete:
  - Current WGS1.2: `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_current_hg38_1004_20260615T080558Z/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv`
  - Prior WGS1.0: `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_prior_hg38_1004_20260615T082114Z/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv`
- Sentieon BWA plus doppelmark alignstats dry-run passed in current clone with `RETURN CODE: 0`.
- Live Sentieon BWA plus doppelmark alignstats launched through DayOA tmux sessions:
  - Current session `hg003_pg_current_alignstats_sent_dmd_1008`; Slurm job `5712`, rule `sentieon_bwa_sort`, partition `i384nvme`, memory `300000M`.
  - Prior session `hg003_pg_prior_alignstats_sent_dmd_1008`; Slurm job `5713`, rule `sentieon_bwa_sort`, partition `i384nvme`, memory `300000M`.
- No alignstats `other_reports` outputs existed yet at this status check.
- Temporary RTG memory watchdog session `hg003_pg_rtg_mem_watch_150g` was stopped after RTG/concordance completion.
