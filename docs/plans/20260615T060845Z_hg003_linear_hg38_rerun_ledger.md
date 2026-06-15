# HG003 June Linear hg38 Rerun Ledger

Created: 2026-06-15T06:08:45Z

## Objective

Rerun the June HG003 30x linear Sentieon workflow in a fresh `day-clone -t 10.0.4` analysis directory, but activate the DayOA Slurm profile with `dy-a slurm hg38` instead of `hg38_broad`.

The rerun keeps the June linear scope:

- Sentieon BWA alignment: `sent`
- Doppelmark deduplication: `dmd`
- Sentieon DNAscope SNV/indel caller: `sentd`
- Concordance: `produce_snv_concordances`

## Gate 0 Inventory

| Check | Evidence |
| --- | --- |
| Local repo | `/Users/jmajor/projects/lsmc/daylily-omics-analysis` |
| Local branch/head | `jem-dev`; `13b324a52ba8a5b2edb12dd685403c8e8cddd6c2` |
| Existing local dirty/untracked state | Pre-existing untracked `docs/plans/20260615T052434Z_altairval_hg003_ultima_*`, `docs/plans/20260615T053844Z_hg003_agbt_feb_linear_compare_ledger.md`, `docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/`, and `jem/`. Do not alter unrelated files. |
| Remote cluster | `dyecX4`, region `us-west-2`, headnode `i-05815cdeec4a6dad8`, AWS profile `lsmc` |
| Previous June run | `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/daylily-omics-analysis` |
| Previous June code | `git describe --tags --always --dirty` -> `10.0.4-dirty`; `git rev-parse HEAD` -> `b0e35b9de7288031c605a480dad35a7225811479` |
| Previous June FASTQs | `HG003_30x_R1.fastq.gz` and `HG003_30x_R2.fastq.gz` under `/fsx/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/` |
| Previous June truth | `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG003/` |
| Previous June command | `produce_sent_align produce_dmd_dedup_cram produce_sentD_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime --config aligners=["sent"] dedupers=["dmd"] snv_callers=["sentd"]` |
| Previous run-local memory profile | `config/day_profiles/slurm/config.yaml` default `mem_mb=100000`; `rtg_vcfeval.mem_mb=650000`; `rtg_vcfeval.parse_mem_mb=128000`; `partition_other=i384nvme,i192hugenvme` |
| Literal `10.0.4` tag memory profile | `mem_mb=3000`; `rtg_vcfeval.mem_mb=64000`; this must be patched in the run-local clone before live launch to preserve the current memory contract. |
| Queue preflight | `day-clone`, `tmux`, and `squeue` present on headnode; `squeue -u ubuntu` empty at preflight. |
| Workflow launch contract | Use persistent `ubuntu` tmux/login pane; commands are sent separately: `day-clone -t 10.0.4`, copy explicit config/profile files, `source dyoainit`, `dy-a slurm hg38`, then `dy-r ...`. No direct `snakemake` invocation. |

## Planned Analysis

| Field | Value |
| --- | --- |
| Workset | `hg003_ilmn30x_linear_sentd_hg38_1004_20260615T060845Z` |
| Analysis path | `/fsx/analysis_results/dyecX4/hg003_ilmn30x_linear_sentd_hg38_1004_20260615T060845Z/daylily-omics-analysis` |
| Tmux session | `hg003_linear_hg38_1004_060845` |
| Clone command | `day-clone -t 10.0.4 -d hg003_ilmn30x_linear_sentd_hg38_1004_20260615T060845Z` |
| Activation | `dy-a slurm hg38` |
| Dry run | `dy-r produce_sent_align produce_dmd_dedup_cram produce_sentD_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime --config aligners=["sent"] dedupers=["dmd"] snv_callers=["sentd"] -n` |
| Live run | `dy-r produce_sent_align produce_dmd_dedup_cram produce_sentD_vcf produce_snv_concordances -p -j 12 -k -T 0 --rerun-triggers mtime --config aligners=["sent"] dedupers=["dmd"] snv_callers=["sentd"]` |

## Execution Rows

| ID | Scope | Status | Evidence | Terminal Note |
| --- | --- | --- | --- | --- |
| PREFLIGHT-001 | Inspect previous June run config, FASTQs, truth, command, and run-local memory profile. | DONE | Remote readback from previous June analysis path confirmed units/samples, `day_cmd.log`, default `mem_mb=100000`, `rtg_vcfeval.mem_mb=650000`, `rtg_vcfeval.parse_mem_mb=128000`. | Previous `10.0.4-dirty` run-local profile must be carried to the new clone. |
| LAUNCH-001 | Create fresh `day-clone -t 10.0.4` analysis directory. | DONE | Persistent tmux session `hg003_linear_hg38_1004_060845` ran `day-clone -t 10.0.4 -d hg003_ilmn30x_linear_sentd_hg38_1004_20260615T060845Z`; `day-clone` cloned to `/fsx/analysis_results/dyecX4/hg003_ilmn30x_linear_sentd_hg38_1004_20260615T060845Z/daylily-omics-analysis` and checked out `b0e35b9de7288031c605a480dad35a7225811479`. | Initial polling expected `/fsx/analysis_results/ubuntu/...`, but `day-clone` used configured clone root `/fsx/analysis_results/dyecX4/...`; corrected path recorded. |
| CONFIG-001 | Stage the same June `samples.tsv`, `units.tsv`, and high-memory Slurm profile into the new clone. | DONE | Direct readback from `/fsx/analysis_results/dyecX4/hg003_ilmn30x_linear_sentd_hg38_1004_20260615T060845Z/daylily-omics-analysis`: copied previous June `samples.tsv` and `units.tsv`; `dy-a slurm hg38` completed; active Slurm profile has default `mem_mb=100000`, `rtg_vcfeval.mem_mb=650000`, `rtg_vcfeval.parse_mem_mb=128000`, and `partition_other=i384nvme,i192hugenvme`. | Same inputs/truth as June `hg38_broad` run, with `hg38` activation and high-memory profile. |
| DRYRUN-001 | Run `dy-a slurm hg38` and `dy-r ... -n` from the persistent tmux pane. | DONE | Dry run returned `RETURN CODE: 0`; DAG had 28 jobs including `sentieon_bwa_sort`, `doppelmark_dups`, `sent_DNAscope`, 6 `rtg_vcfeval_roi`, and `produce_snv_concordances`; outputs are under `results/day/hg38/...`. | Dry run succeeded with the requested `hg38` activation and explicit `sent/dmd/sentd` config. |
| RUN-001 | Launch live `dy-r` run for `sent+dmd+sentd+concordance`. | IN_PROGRESS | Live `dy-r` command launched from tmux session `hg003_linear_hg38_1004_060845`; Snakemake controller process observed under `bin/day_run`; first submitted job was `sentieon_bwa_sort` as Slurm job `5622`. | Run is active. |
| MONITOR-001 | Verify tmux, controller/process state, Slurm queue, and first Snakemake log after live launch. | IN_PROGRESS | Initial status: job `5622`, rule `sentieon_bwa_sort`, partition `i384nvme`, moved from `CF` to `RUNNING` on `i384nvme-dy-price384nvme-1`; Sentieon alignment log reports instance `c8id.96xlarge`, version `sentieon-genomics-202503.02`, and reference `/fsx/references/genomic_data/organism_references/H_sapiens/hg38/fasta_fai_minalt/GRCh38_no_alt_analysis_set.fasta`. Alignment completed with `724305354` reads, `output file size: 46996246413`, `Elapsed-Time-min: c8id.96xlarge 21`; sorted BAM and BAI present. Doppelmark completed in `11` minutes with CRAM `10869221049` bytes and nonzero CRAI. DNAscope completed with the same `SentieonIlluminaWGS2.2.bundle/dnascope.model` and `pop-v20g41-20251216.vcf.gz`; workflow reached `24 of 28 steps (86%) done`; one RTG job remained running. | Monitoring active run. |
| RESULTS-001 | Report `giabHC` Fscore/recall/precision for SNPts, SNPtv, INS_50, and DEL_50 when complete. | IN_PROGRESS | Direct `_giabHC` mqc rows are present before final aggregate report: SNPts F-score `0.9968114926574638`, recall `0.9957327071739398`, precision `0.9978926182074053`; SNPtv F-score `0.9964300799253253`, recall `0.9951811250008157`, precision `0.9976821736724837`; INS_50 F-score `0.9978508098874718`, recall `0.9968780402226439`, precision `0.9988254798953319`; DEL_50 F-score `0.9979470901977505`, recall `0.9970968187286748`, precision `0.9987988130376201`. | Awaiting final `results/day/hg38/other_reports/giab_concordance_mqc.tsv`. |
