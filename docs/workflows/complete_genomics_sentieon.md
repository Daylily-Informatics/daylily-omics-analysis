# Complete Genomics / MGI Sentieon Workflow

This is the current Complete Genomics T7+ / MGI-style WGS path.

## Route

Use:

- aligner: `sentcg`
- deduper: `smd`
- SNV caller: `cgt7p`

```bash
dy-r produce_sentcg_align produce_smd_dedup_cram produce_cgt7p_snv_vcf \
  produce_alignstats produce_snv_concordances \
  -p -j 20 -k -T 1 --retries 0 --rerun-incomplete --keep-incomplete
```

Dry-run first by adding `-n`.

## Model And Read-Group Settings

The local and Slurm profile templates configure the MGI-specific Sentieon bundle:

| Config key | Value |
| --- | --- |
| `sentieon_cgt7p.bwa_model` | `/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/DNAscopeMGIWGS2.1.bundle/bwa.model` |
| `sentieon_cgt7p.read_group_platform` | `DNBSEQ` |
| `cgt7p.dna_scope_snv_model` | `/fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/DNAscopeMGIWGS2.1.bundle/dnascope.model` |

The DNAscope rule uses `--pcr_indel_model none`.

## Inputs

Use normal `config/samples.tsv` plus `config/units.tsv` tables. The Complete Genomics path consumes FASTQ columns through the short-read code path and supports `SUBSAMPLE_PCT`.

For downsample grids, keep `SAMPLEID` tied to the biological sample and make each analysis unit distinct with unit-level identifiers such as `EXPERIMENTID` and `BARCODEID`. This prevents multiple downsample percentages from collapsing into one analysis unit.

`SUBSAMPLE_PCT` must be a float in `(0.0, 1.0]`; use `na` or empty for no downsampling.

## Outputs

For each sample/unit:

| Stage | Output pattern |
| --- | --- |
| Sentieon CG alignment | `results/day/<build>/<sample>/align/sentcg/<sample>.sentcg.sort.bam` and `.bai` |
| Sentieon dedup | `results/day/<build>/<sample>/align/sentcg/smd/<sample>.sentcg.smd.cram` and `.crai` |
| CG DNAscope | `results/day/<build>/<sample>/align/sentcg/smd/snv/cgt7p/<sample>.sentcg.smd.cgt7p.snv.sort.vcf.gz` and `.tbi` |
| Concordance | `results/day/<build>/<sample>/align/sentcg/smd/snv/cgt7p/concordance/` |
| Aggregate GIAB report | `results/day/<build>/other_reports/giab_concordance_mqc.tsv` |
| Aggregate alignstats | `results/day/<build>/other_reports/alignstats_combo_mqc.tsv` |
| Benchmark summary | `results/day/<build>/reports/benchmarks_summary.tsv` |

The `sentcg.sort.bam` and `.bai` outputs are declared as Snakemake `temp()` outputs. They may be removed after successful downstream completion unless temp preservation is requested. `bin/day_run` translates `--keep-temp` to Snakemake `--notemp`.

## Monitoring

When monitoring a running Complete Genomics workset:

1. verify the tmux session has exactly one window and one pane before interacting
2. check `squeue` for only the relevant workdir/jobs
3. inspect the Snakemake controller process
4. tail the latest `.snakemake/log/*.snakemake.log`
5. tail newest relevant `logs/slurm/<rule>/*.{out,err}`
6. tail the stable active rule log under `results/day/<build>/<sample>/.../logs/`
7. from the already connected SSM headnode shell, inspect active compute nodes by Slurm node name with `bash -l -c` and check `/dev/shm`, memory, load, and relevant `sentieon`, `samtools`, `mbuffer`, `day_run`, and `snakemake` processes

Do not make AWS infrastructure changes or touch unrelated Slurm jobs while debugging this workflow.

## Validation Hooks

The current tests assert the key routing and model facts:

```bash
python -m pytest tests/test_complete_genomics_sentieon.py
```

That test verifies the MGI model paths, `DNBSEQ` platform, and the routing from `produce_cgt7p_snv_vcf` to `sentcg` and `cgt7p`.
