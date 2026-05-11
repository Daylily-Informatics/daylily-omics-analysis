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
| `produce_sentD_vcf` | Illumina Sentieon DNAscope. |
| `produce_deep19_vcf` | DeepVariant 1.9. |
| `produce_sentdont_vcf` | ONT Sentieon SNV calling. |
| `produce_sentdpb_vcf` | PacBio Sentieon SNV calling. |
| `produce_sentdug_vcf` | Ultima Genomics SNV calling. |
| `produce_cgt7p_vcf` | Complete Genomics/MGI Sentieon DNAscope via `sentcg`. |
| `produce_sentdhiom_vcf` | Modular Illumina+ONT hybrid workflow. |
| `produce_sentdhuom_vcf` | Modular Ultima+ONT hybrid workflow. |
| `produce_manta`, `produce_tiddit`, `produce_duphold` | Structural variant workflows and SV annotation. |
| `produce_htd_calls` | Selected HTD/special callers from `--config htd_callers=[...]`. |
| `produce_altair_validation_artifacts` | Altair validation artifact package using controlled RR/BAR manifests and full-RR coverage/callability. |
| `produce_multiqc_seq_data` | MultiQC for input sequence-data QC. |
| `produce_multiqc_alignment` | MultiQC for sequence-data plus alignment and contamination QC. |
| `produce_multiqc_variants` | MultiQC for sequence, alignment, and variant/annotation QC. |
| `produce_multiqc_final`, `produce_multiqc_final_wgs` | Final routine MultiQC aggregation. |

Use `dy-r help` and tab completion for the full target list.
