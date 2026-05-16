# Daylily CLI

The Daylily CLI is a set of shell entrypoints around Snakemake. Run commands from an analysis clone, usually under `/fsx/analysis_results/ubuntu/<workset>/daylily-omics-analysis` on a headnode created by `daylily-ephemeral-cluster`.

Use `daylily-ec` for supported headnode access, sample staging, and manifest creation or delivery. The workflow assumes Daylily omics/reference data are mounted at `/fsx/data`; many supporting-file paths are intentionally absolute to that mount.

## Basic Pattern

```bash
source dyoainit
dy-a slurm hg38

dy-r produce_snv_concordances -p -k -j 20 -n
dy-r produce_snv_concordances -p -k -j 20
```

Use `dy-a local hg38` for local debugging and smoke tests.

## Commands

| Command | Alias | Purpose |
| --- | --- | --- |
| `day-activate` | `dy-a` | Activate an executor profile and genome build. |
| `day-run` | `dy-r` | Build and execute the Snakemake command. |
| `day-monitor` | `dy-m` | Display command history, Slurm status, master log tails, and recent Slurm logs. |
| `day-set-genome-build` | `dy-g` | Change the active genome build. |
| `day-deactivate` | `dy-d` | Reset Daylily shell state. |

`source dyoainit` wires these aliases/functions into the current shell. Source it; do not execute it as a subprocess.

## Common `dy-r` Flags

| Flag | Meaning |
| --- | --- |
| `-n` | Dry-run only. |
| `-p` | Print shell commands. |
| `-k` | Keep independent jobs going after a failure. |
| `-j N` | Limit active Snakemake jobs. |
| `-T N` | Snakemake retry/attempt flag used by existing Daylily run commands. |
| `--retries N` | Snakemake retry attempts in long form. |
| `--rerun-incomplete` | Re-run incomplete outputs. |
| `--keep-incomplete` | Keep failed partial outputs for debugging. |
| `--keep-temp` | Daylily convenience flag translated by `bin/day_run` to Snakemake `--notemp`. |
| `--config key=value` | Override workflow config. Lists are commonly passed as `aligners=[sent]`. |

`bin/day_run` records invocations in `day_cmd.log`.

## Monitoring

```bash
dy-m
dy-m --interval 10
dy-m --workdir /fsx/analysis_results/ubuntu/<workset>/daylily-omics-analysis
dy-m --block-and-poll --interval 30
```

`day-monitor` reports:

1. directory and marker status
2. last commands from `day_cmd.log`
3. Slurm queue status
4. latest Snakemake master-log tail
5. recent Slurm log tails

For manual debugging, use this order:

1. `squeue -u ubuntu`
2. `ps -fu ubuntu | grep -E 'snakemake|day_run|dy-r'`
3. latest `.snakemake/log/*.snakemake.log` by mtime
4. newest relevant `logs/slurm/<rule>/*.{out,err}` by mtime
5. stable rule log under `results/day/<build>/<sample>/.../logs/`

## Common Targets

| Target | Description |
| --- | --- |
| `produce_alignstats` | Alignment statistics and aggregate report. |
| `produce_snv_concordances` | GIAB/RTG concordance for available truth data. |
| `produce_sentd_snv_vcf` | Illumina Sentieon DNAscope. |
| `produce_deep19_snv_vcf` | DeepVariant 1.9. |
| `produce_sentdont_snv_vcf` | ONT Sentieon SNV calling. |
| `produce_sentdpb_snv_vcf` | PacBio Sentieon SNV calling. |
| `produce_sentdug_snv_vcf` | Ultima Genomics SNV calling. |
| `produce_cgt7p_snv_vcf` | Complete Genomics/MGI Sentieon DNAscope via `sentcg`. |
| `produce_sentdhiom_snv_vcf` | Modular Illumina+ONT hybrid workflow. |
| `produce_sentdhuom_snv_vcf` | Modular Ultima+ONT hybrid workflow. |
| `produce_dmd_dedup_cram`, `produce_smd_dedup_cram`, `produce_na_dedup_cram` | Canonical dedup selector targets; legacy `dppl` normalizes to `dmd`. |
| `produce_all_align`, `produce_all_dedup_cram`, `produce_all_snv_vcf`, `produce_all_sv_vcf` | Run every registered selector in that stage, subject to manifest/platform compatibility. |
| `produce_manta_sv_vcf`, `produce_tiddit_sv_vcf`, `produce_dysgu_sv_vcf` | Structural variant workflows. |
| `produce_htd_calls` | Selected HTD/special callers from `--config htd_callers=[...]`. |
| `produce_multiqc_input_data` | MultiQC for input sequence-data QC. |
| `produce_multiqc_cram` | MultiQC for CRAM/alignment QC. |
| `produce_multiqc_snv`, `produce_multiqc_sv` | MultiQC for SNV and SV QC scopes. |
| `produce_multiqc_sample_qc` | MultiQC for sample-level contamination, relatedness, and sex/QC signals. |
| `produce_multiqc_variant_annotation` | MultiQC for VEP/SnpEff and other annotation summaries. |
| `produce_multiqc_all` | Canonical final routine MultiQC aggregation. |

Use `dy-r help` and tab completion for the full target list.
Legacy selector and MultiQC targets remain available but are marked as
deprecated; prefer the canonical names in new runbooks.
