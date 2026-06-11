# dyecX4 Doppelmark, ONT Plumbing, and Ultima Kitchensink Ledger

## Scope

Cluster: `dyecX4`
AWS profile: `lsmc`
Region: `us-west-2`
DayOA baseline: `10.0.3`
DYEC workflow execution contract: persistent `ubuntu` tmux pane with `source dyoainit`, `dy-a ...`, and `dy-r ...`; never raw `snakemake`.

Requested changes:
- Request at least 600 GB for Slurm `doppelmark`.
- Fix ONT DNAscope long-read flag plumbing so the population VCF is passed with `--pop_vcf`.
- Re-run Ultima pangenome with a kitchensink target set including MultiQC, mosdepth/goleft-style alignstats, contamination/identity, metagenomics, VEP, and concordance.

## Gate 0 Baseline

| Row | Owner | State | Evidence |
| --- | --- | --- | --- |
| G0-001 | orchestrator | PASS | `git status --short --branch` in DayOA: `## jem-dev...origin/jem-dev` |
| G0-002 | orchestrator | PASS | `git describe --tags --always --dirty` in DayOA: `10.0.3` |
| G0-003 | orchestrator | PASS | `git status --short --branch` in DYEC: `## jem-dev...origin/jem-dev` |
| G0-004 | orchestrator | PASS | Required DayOA headnode workflow instructions read from `/Users/jmajor/.codex/AGENTS-HOW-TO-RUN-DAYOA.md` |

## Ledger Rows

| Row | Owner | State | Action | Evidence / Notes |
| --- | --- | --- | --- | --- |
| CODE-001 | agent-code | PASS | Raise Slurm `doppelmark.mem_mb` to at least `600000`. | Patched `config/day_profiles/slurm/templates/rule_config.yaml`. |
| CODE-002 | agent-code | PASS | Fix ONT `dnascope-longread` params so dbSNP remains on `-d` and population VCF uses `--pop_vcf`. | Patched `workflow/rules/sent_snv_ont.smk`; local/slurm `sentdont.pop_vcf` now has the pangenome population VCF. |
| TEST-001 | agent-code | PASS | Run focused pytest coverage for ONT contract, model bundle config, and Slurm profile resources. | `python -m pytest tests/test_ont_fastq_contracts.py tests/test_sentieon_model_bundle_config.py tests/test_slurm_profile.py -q`: `19 passed in 0.47s`. |
| CODE-003 | agent-code | PASS | Allow mixed Ultima source-CRAM QC and pangenome `sentpg` variant QC in one kitchensink DAG. | Patched graph-only pangenome aligner handling and fixed `sentpg`/`spmd` variant paths in common, concordance, VEP, BCFtools VCF stats, and RTG VCF stats. |
| TEST-002 | agent-code | PASS | Run pangenome kitchensink contract tests. | `python -m pytest tests/test_ont_fastq_contracts.py tests/test_sentieon_model_bundle_config.py tests/test_slurm_profile.py tests/test_pangenome_kitchensink_contracts.py -q`: `22 passed in 0.44s`. |
| CODE-004 | agent-code | PASS | Restrict CRAM/alignment QC target fan-out to real CRAM-capable aligners. | Patched dedup target gathers, alignstats, coverage-evenness, legacy alignment MultiQC, and Picard target gathers. |
| TEST-003 | agent-code | PASS | Re-run focused tests after CRAM-QC fan-out patch. | `python -m pytest tests/test_ont_fastq_contracts.py tests/test_sentieon_model_bundle_config.py tests/test_slurm_profile.py tests/test_pangenome_kitchensink_contracts.py -q`: `23 passed in 0.42s`. |
| CODE-005 | agent-code | PASS | Restrict target-alias `na` dedup expansion away from graph-only pangenome aligners. | Patched `workflow/rules/workflow_target_aliases.smk` after dry-run showed `produce_na_dedup_cram` requested impossible `pangenome_ug/na` CRAM paths. |
| CODE-006 | agent-code | PASS | Restrict metagenomics and final MultiQC staging to real CRAM-QC aligners. | Patched `workflow/rules/unmapped_metagenomics.smk` and `workflow/rules/multiqc_final_wgs.smk` after enabling `metagenomics` requested impossible `pangenome_ug/na` CRAM inputs. |
| TEST-004 | agent-code | PASS | Re-run focused tests after target-alias and metagenomics fan-out patches. | `python -m pytest tests/test_ont_fastq_contracts.py tests/test_sentieon_model_bundle_config.py tests/test_slurm_profile.py tests/test_pangenome_kitchensink_contracts.py -q`: `25 passed in 0.42s`. |
| RUN-001 | agent-ultima | PASS | Identify prior Ultima pangenome sample/config source and create a fresh kitchensink analysis id. | Fresh analysis `pg_ultima_hg003_30x_pangenome_multiqc_kitchensink_20260610T093038Z` cloned at DayOA `10.0.3`; sample/unit TSVs copied from `pg_ultima_hg003_30x_pangenome_concordance_20260609T194248Z`. Accidental default-entity clone was created under `/fsx/analysis_results/dyecX4/...` and left untouched. |
| RUN-002 | agent-ultima | PASS | Launch Ultima pangenome kitchensink dry-run through `dy-r` in persistent tmux. | `DRYRUN_METAGENOMICS_FIX_20260610T095207Z` returned `0`; planned 121 jobs including `sentieon_pangenome_ug` 128 threads, mosdepth, goleft, GATK contamination, site-mix contamination, Kraken2/Ganon2/sourmash metagenomics, VEP, SNV concordance, final MultiQC, and evidence manifest. |
| RUN-003 | agent-ultima | IN_PROGRESS | Launch Ultima pangenome kitchensink live run through `dy-r` in persistent tmux. | `LIVE_ULTIMA_PANGENOME_KITCHENSINK_20260610T095230Z` launched without `-n` in tmux `pg_ultima_hg003_30x_multiqc_20260610T093038Z`; initial state was conda environment creation for `workflow/envs/gatkcontam_v0.1.yaml`. |
| MON-001 | orchestrator | PASS | Capture initial tmux/squeue status after launch. | `squeue` showed the Snakemake controller active for `pg_ultima_hg003_30x_pangenome_multiqc_kitchensink_20260610T093038Z` and no competing workflow controller. |
| RUN-003A | agent-ultima | FAIL | Capture first live terminal state. | Live run failed before final MultiQC/export in `vep_chromosome`; pane showed failed VEP chromosome chunks and `RETURN CODE: 1`; S3 export prefix had 0 objects. |
| CODE-007 | agent-code | PASS | Reduce VEP fork pressure and add pre-VEP rule diagnostics. | Patched `vep.threads=8`, `vep.mem_mb=128000`, and VEP rule log header; uploaded patch files to `s3://lsmc-dayoa-analysis-results-usw2/validation/dyecX4/10.0.13/patches/ultima_kitchensink_vep_retry_20260610T203700Z/`; deployed to existing FSx checkout with backups. |
| TEST-005 | agent-code | PASS | Re-run focused tests after VEP resource patch. | `python -m pytest tests/test_multiqc_qc_targets.py::test_variant_qc_and_annotation_summaries_are_wired tests/test_pangenome_kitchensink_contracts.py -q`: `7 passed in 0.11s`. |
| RUN-004 | agent-ultima | PASS | Resume dry-run after VEP resource patch. | `dy-r ... produce_vep produce_metagenomics produce_multiqc_all ... -j 80 -n` returned `0` in tmux `pg_ultima_hg003_30x_multiqc_20260610T093038Z`. |
| RUN-005 | agent-ultima | FAIL | Launch patched live retry. | Live retry submitted some non-VEP jobs, then failed at VEP submission because `i384` is not a valid dyecX4 partition; existing submitted jobs were left untouched and monitored read-only. |
| CODE-008 | agent-code | PASS | Correct VEP partition from `i384` to `i384nvme`. | Patched local Slurm template and test assertion; focused tests returned `7 passed in 0.12s`; uploaded corrected profile to `s3://lsmc-dayoa-analysis-results-usw2/validation/dyecX4/10.0.13/patches/ultima_kitchensink_vep_retry_20260610T204500Z/`; deployed to both template and active FSx profile with `vep.partition=i384nvme,i192,i128`. |
| MON-002 | orchestrator | IN_PROGRESS | Wait for already-submitted orphan jobs to clear before resume. | Read-only `squeue` showed jobs 177-184 in `CF`; no Slurm cancellation/requeue/drain/resume performed. |
