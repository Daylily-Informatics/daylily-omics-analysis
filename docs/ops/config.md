# Configuring Daylily

Daylily keeps most run behavior in Snakemake profiles and manifest tables rather than hard-coding values inside rules. Production profiles are tuned for `daylily-ephemeral-cluster` headnodes and the Daylily omics/reference data mount at `/fsx/data`.

## Required Run Tables

Current runs use:

- `config/samples.tsv`
- `config/units.tsv`

For production worksets, create or deliver these tables through `daylily-ec` staging. The tables should point at staged read data and supporting resources visible from the headnode and compute nodes, especially `/fsx/data` reference paths.

`config/analysis_manifest.csv` is legacy. See [`analysis_manifest.md`](analysis_manifest.md) only when converting older run notes.

## `samples.tsv`

One row per biological sample. Important columns include:

- `SAMPLEID`
- `SAMPLESOURCE`
- `SAMPLECLASS`
- `BIOLOGICAL_SEX`
- `CONCORDANCE_CONTROL_PATH`
- `IS_POSITIVE_CONTROL`
- `IS_NEGATIVE_CONTROL`
- `SAMPLE_TYPE`
- `EXTERNAL_SAMPLE_ID`
- `TRUTH_DATA_DIR`
- `COMMENT` (optional free-text operator note)

The schema source is `workflow/schemas/samples.schema.yaml`.

## `units.tsv`

One row per sequencing unit or analysis unit. Important columns include:

- `RUNID`
- `SAMPLEID`
- `EXPERIMENTID`
- `LANEID`
- `BARCODEID`
- `LIBPREP`
- `SEQ_VENDOR`
- `SEQ_PLATFORM`
- FASTQ columns such as `ILMN_R1_PATH` and `ILMN_R2_PATH`
- platform-specific CRAM/BAM columns such as `ONT_BAM`, `UG_R1_PATH`, `ROCHE_BAM`
- `SUBSAMPLE_PCT`
- `COMMENT` (optional free-text run/lane/library note)

The schema source is `workflow/schemas/units.schema.yaml`.

`SUBSAMPLE_PCT` is validated as a float in `(0.0, 1.0]`. Use `na` or an empty value when no downsampling should occur.

## Profiles

Profiles live under `config/day_profiles/`.

| Profile | Use |
| --- | --- |
| `local` | Local smoke tests and small debugging runs. |
| `slurm` | AWS ParallelCluster headnode execution. |

Each profile template includes:

- Snakemake profile config
- per-rule resource and model settings in `rule_config.yaml`
- Slurm executor settings for the Slurm profile

Activate a profile with:

```bash
source dyoainit
dy-a local hg38
```

or, on a prepared headnode:

```bash
source dyoainit
dy-a slurm hg38
dy-a slurm hg38_broad
```

Supported build names are currently `hg38`, `hg38_broad`, and `b37`.

## Config Precedence

Canonical target selectors should be used for routine aligner, deduper, SNV,
and SV caller selection:

```bash
dy-r produce_sent_align produce_dmd_dedup_cram produce_sentd_snv_vcf \
  produce_snv_concordances \
  -p -j 20
```

Run-level overrides can still be passed with Snakemake `--config` through
`dy-r` for non-selector settings such as optional QC gates, HTD callers, or
reference/debug overrides.

Common code selectors:

| Selector | Examples |
| --- | --- |
| `aligners` | `sent`, `sentcg`, `bwa2a`, `strobe` |
| `dedupers` | `dmd`, `smd`, `na` |
| `snv_callers` | `sentd`, `cgt7p`, `deep19`, `oct`, `clair3`, `lfq2` |

Use target-specific docs before mixing selectors; not every caller is valid for
every aligner. New runbooks should prefer canonical target selectors, which
populate these values automatically when possible. For example, `produce_sent_align`,
`produce_dmd_dedup_cram`, `produce_sentd_snv_vcf`, and
`produce_manta_sv_vcf` remove the need to pass `aligners=[sent]`,
`dedupers=[dmd]`, `snv_callers=[sentd]`, or `sv_callers=[manta]` explicitly.
The legacy deduper code `dppl` still normalizes to `dmd`, but it is not a
current selector value.

## Scratch And Temp Files

Rule scratch locations are profile-configured. The current Complete Genomics Sentieon path uses persistent worktree scratch through `TMPDIR`/`SENTIEON_TMPDIR`, not `/dev/shm`, for Sentieon sort and DNAscope scratch.

Some intermediate outputs are declared as Snakemake `temp()`. For example, `sentcg.sort.bam` is temporary once downstream CRAM/VCF outputs complete. If an operator wants temp outputs retained for a diagnostic run, pass `--keep-temp`; `bin/day_run` translates it to Snakemake `--notemp`.
