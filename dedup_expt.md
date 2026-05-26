# 7GIAB 30x Deduper Comparison: hg38, sent, dmd/smd/na

This is the run note for starting the same 7GIAB 30x hg38 analysis with three dedup scenarios:

- `dmd`: Doppelmark duplicate marking
- `smd`: Sentieon duplicate marking
- `na`: no dedup passthrough

Use the canonical deduper code `dmd` for new runs. The older CLI value `dppl` is accepted by the workflow and maps to `dmd`, but using `dmd` avoids ambiguity in result paths and MultiQC sample IDs.

## Inputs

- Samples: `HG001` through `HG007`
- Genome build: `hg38`
- Aligner: `sent`
- SNV caller: `sentd`
- FASTQ root:
  `/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007/`
- Truth/control resources:
  `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/<sample>/`
- Source sample manifest template in repo:
  `.test_data/data/giab_30x_hg38_analysis_manifest.samples.tsv`

For a true 30x run, `SUBSAMPLE_PCT` in `config/units.tsv` must be `na` or empty. Do not reuse a 5x `units.tsv` with `SUBSAMPLE_PCT=0.1666666667`.

## Start A New Workset

From the Mac, activate the cluster CLI environment:

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
AWS_PROFILE=lsmc daylily-ec headnode connect --profile lsmc --region us-west-2 --cluster <cluster>
```

On the headnode, use an interactive login bash shell as `ubuntu`. Create a unique workset so no existing result data is touched:

```bash
id -un
echo "$0"
exec bash -l

cd /fsx/analysis_results/ubuntu
day-clone -t <git-ref-or-tag> -d 7giab-30x-dedup-YYYYMMDD
cd /fsx/analysis_results/ubuntu/7giab-30x-dedup-YYYYMMDD/daylily-omics-analysis
```

## Build 30x Manifests

Generate the 7GIAB Illumina manifest scaffold, then convert the units table from the helper's 5x defaults to 30x:

```bash
mkdir -p config
python scripts/generate_giab7_ilmn5x_manifests.py --output-dir config --check-inputs

awk 'BEGIN{FS=OFS="\t"} NR==1{print; next} {$1="giab7-30x-dedup-YYYYMMDD"; $3="ilmn30x"; $17="na"; print}' \
  config/units.tsv > config/units.tsv.tmp
mv config/units.tsv.tmp config/units.tsv

wc -l config/samples.tsv config/units.tsv
awk -F'\t' 'NR==1 || NR<=8 {print $1, $2, $3, $17, $9, $10}' OFS='\t' config/units.tsv
```

Expected manifest counts:

- `config/samples.tsv`: 8 lines, header plus 7 samples
- `config/units.tsv`: 8 lines, header plus 7 units
- `SUBSAMPLE_PCT`: `na` for every unit

## Activate DayOA

Run these as separate commands in the interactive headnode shell:

```bash
source dyoainit
dy-a slurm hg38
```

## Dry Run

```bash
dy-r produce_alignstats produce_snv_concordances produce_multiqc_final \
  -p -k \
  --config 'aligners=["sent"]' 'dedupers=["dmd","smd","na"]' 'snv_callers=["sentd"]' \
  -j 100 --rerun-triggers mtime -n
```

Check that the DAG includes all three dedup paths under:

```text
results/day/hg38/<sample>/align/sent/dmd/
results/day/hg38/<sample>/align/sent/smd/
results/day/hg38/<sample>/align/sent/na/
```

Also confirm the final report inputs include:

- alignstats for `sent.dmd`, `sent.smd`, and `sent.na`
- RTG/GIAB concordance for `sent.dmd.sentd`, `sent.smd.sentd`, and `sent.na.sentd`
- final MultiQC report components

## Launch

Use a persistent tmux session so the run remains inspectable after disconnect:

```bash
tmux new-session -d -s giab7_30x_dedup_YYYYMMDD
tmux send-keys -t giab7_30x_dedup_YYYYMMDD 'cd /fsx/analysis_results/ubuntu/7giab-30x-dedup-YYYYMMDD/daylily-omics-analysis' Enter
tmux send-keys -t giab7_30x_dedup_YYYYMMDD 'source dyoainit' Enter
tmux send-keys -t giab7_30x_dedup_YYYYMMDD 'dy-a slurm hg38' Enter
tmux send-keys -t giab7_30x_dedup_YYYYMMDD 'dy-r produce_alignstats produce_snv_concordances produce_multiqc_final -p -k --config '"'"'aligners=["sent"]'"'"' '"'"'dedupers=["dmd","smd","na"]'"'"' '"'"'snv_callers=["sentd"]'"'"' -j 100 --rerun-incomplete --rerun-triggers mtime' Enter
```

Monitor from a second interactive shell:

```bash
tmux capture-pane -pt giab7_30x_dedup_YYYYMMDD -S -120
squeue -u ubuntu | head -80
tail -120 .snakemake/log/$(ls -1t .snakemake/log | head -1)
```

## Acceptance Checks

The run is ready to review when:

- latest Snakemake master log ends with `WORKFLOW SUCCESS`
- `squeue -u ubuntu` has no jobs from this workdir
- final report exists:
  `results/day/hg38/reports/DAY_final_multiqc.html`
- aggregate concordance exists:
  `results/day/hg38/other_reports/giab_concordance_mqc.tsv`
- alignstats aggregate exists:
  `results/day/hg38/other_reports/alignstats_combo_mqc.tsv`
- report sample IDs show deduper-specific identities, for example:
  `HG002.sent.dmd`, `HG002.sent.smd`, `HG002.sent.na`
- concordance rows show full SNV identity, for example:
  `HG002.sent.dmd.sentd.All`

Optional VEP extension: if the run should include VEP, add `produce_vep` to the target list and include `multiqc_qc={"enable_tools":["vep"]}` in the config. Keep VEP out of the core dedup comparison unless annotation runtime is part of the experiment.
