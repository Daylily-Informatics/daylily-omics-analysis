# HG003 Altair ILMN + ONT Hybrid Analysis Status

## Summary

This report summarizes the HG003 Altair Illumina plus ONT validation work currently completed on `hyb-hg003`, and separates it from the downsample HIOMR matrix that is prepared but not yet run.

- Cluster: `hyb-hg003`
- Region: `us-west-2`
- FSx filesystem: `fs-04fb08a9a0d8a6752`
- Headnode: `i-03f1a49bbc4e39d4b`
- DayOA version: `1.0.21`
- DayOA repository: `https://github.com/Daylily-Informatics/daylily-omics-analysis.git`
- Current `/fsx` status at report creation: `8.8T` total, `1.6T` used, `7.2T` available
- Slurm status at report creation: no `ubuntu` jobs queued or running
- Current DRA export destination: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/`

## Source Data

### Altair ILMN

- Sample: `HG003-a`
- Sequencer run: `20260514-LH01106-0009-B23TVLGLT4`
- Experiment label: `20260514-ILMN-Altair-Run-3`
- Input shape: 8 matched R1/R2 lane FASTQ pairs
- Lane validation: all 8 lane pairs were validated for lane label, read count, first read name, and last read name pairing.
- Validation TSV: `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/altair_run3_hg003a_lane_pair_validation.tsv`

### ONT

- Sample: `HG003-a`
- Input CRAM: `/fsx/staging/staged_sample_data/remote_stage_20260522T203135Z/20260514-LH01106-0009-B23TVLGLT4_HG003-a-NOVASEQ-PF-gdna-20260514-ILMN-Altair-Run-3_HG003-a_0/HG003_30x.cleaned.cram`
- Input CRAM size observed during staging: `21471428852` bytes

## Completed Full-Coverage Runs

### ILMN Solo Full Coverage

- Workdir: `/fsx/analysis_results/ubuntu/hg003a_altair3_ilmn_full_1021`
- Exported location: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/hg003a_altair3_ilmn_full_1021/`
- Status: completed successfully with `daylily.successful_run`
- Result root: `/fsx/analysis_results/ubuntu/hg003a_altair3_ilmn_full_1021/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats TSV: `other_reports/alignstats_combo_mqc.tsv`
- GIAB concordance TSV: `other_reports/giab_concordance_mqc.tsv`

Command:

```bash
dy-r produce_alignstats produce_sentd_snv_vcf produce_snv_concordances --config 'aligners=["sent"]' 'dedupers=["na"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

Alignment summary:

| Metric | Value |
|---|---:|
| Aligner | `sent` |
| Deduper | `na` |
| Mapped reads | `99.922186%` |
| Mapped bases | `99.922186%` |
| WGS mean coverage | `70.476298` |
| WGS median coverage | `72` |
| Bases at 10x | `93.214482%` |
| Bases at 20x | `92.179639%` |
| Bases at 30x | `90.252394%` |
| Yield reads | `1526373455` |
| Yield bases | `230482391705` |

GIAB concordance summary, `VariantClass=All`:

| ROI | Caller | F-score | Sensitivity | Precision | TP | FP | FN |
|---|---|---:|---:|---:|---:|---:|---:|
| `giabHC` | `sentd` | `0.988940` | `0.978836` | `0.999255` | `3750812` | `2795` | `81099` |
| `giabHC_x_clinvar_genes` | `sentd` | `0.982813` | `0.967143` | `0.998998` | `428841` | `430` | `14569` |
| `clinvar_genes` | `sentd` | `0.897393` | `0.962741` | `0.840353` | `444740` | `84490` | `17212` |
| `hg38` | `sentd` | `0.889931` | `0.976163` | `0.817698` | `3904625` | `870521` | `95347` |

### ONT Solo Full Coverage

- Workdir: `/fsx/analysis_results/ubuntu/hg003a_altair3_ont_full_1021`
- Exported location: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/hg003a_altair3_ont_full_1021/`
- Status: completed successfully with `daylily.successful_run`
- Result root: `/fsx/analysis_results/ubuntu/hg003a_altair3_ont_full_1021/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats TSV: `other_reports/alignstats_combo_mqc.tsv`
- GIAB concordance TSV: `other_reports/giab_concordance_mqc.tsv`

Command:

```bash
dy-r produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances -p -j 5 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

Alignment summary:

| Metric | Value |
|---|---:|
| Aligner | `ont` |
| Deduper | `na` |
| Mapped reads | `100.0%` |
| Mapped bases | `100.0%` |
| WGS mean coverage | `15.643172` |
| WGS median coverage | `16` |
| Bases at 10x | `87.907051%` |
| Bases at 20x | `23.691389%` |
| Bases at 30x | `0.778426%` |
| Yield reads | `2273423` |
| Yield bases | `36040682224` |

GIAB concordance summary, `VariantClass=All`:

| ROI | Caller | F-score | Sensitivity | Precision | TP | FP | FN |
|---|---|---:|---:|---:|---:|---:|---:|
| `giabHC` | `sentdont` | `0.837520` | `0.727865` | `0.986075` | `2789098` | `39388` | `1042792` |
| `giabHC_x_clinvar_genes` | `sentdont` | `0.793920` | `0.665021` | `0.984801` | `294869` | `4551` | `148529` |
| `clinvar_genes` | `sentdont` | `0.736699` | `0.660918` | `0.832107` | `305306` | `61601` | `156636` |
| `hg38` | `sentdont` | `0.750106` | `0.724477` | `0.777615` | `2897907` | `828752` | `1102091` |

### HIOMR Full Coverage

- Workdir: `/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_full_1021`
- Exported location: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/hg003a_altair3_hiomr_full_1021/`
- Status: completed successfully with `daylily.successful_run`
- Result root: `/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_full_1021/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats TSV: `other_reports/alignstats_combo_mqc.tsv`
- GIAB concordance TSV: `other_reports/giab_concordance_mqc.tsv`

Command:

```bash
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

Alignment summary:

| Metric | Value |
|---|---:|
| Aligner | `ont` |
| Deduper | `dmd` |
| Mapped reads | `100.0%` |
| Mapped bases | `100.0%` |
| WGS mean coverage | `15.643172` |
| WGS median coverage | `16` |
| Bases at 10x | `87.907051%` |
| Bases at 20x | `23.691389%` |
| Bases at 30x | `0.778426%` |
| Yield reads | `2273423` |
| Yield bases | `36040682224` |

GIAB concordance summary, `VariantClass=All`:

| ROI | Caller | F-score | Sensitivity | Precision | TP | FP | FN |
|---|---|---:|---:|---:|---:|---:|---:|
| `giabHC` | `sentdhiomr` | `0.996624` | `0.994259` | `0.999000` | `3809891` | `3815` | `21998` |
| `giabHC_x_clinvar_genes` | `sentdhiomr` | `0.994346` | `0.990056` | `0.998674` | `438988` | `583` | `4409` |
| `clinvar_genes` | `sentdhiomr` | `0.904669` | `0.987394` | `0.834734` | `456113` | `90304` | `5823` |
| `hg38` | `sentdhiomr` | `0.888297` | `0.992738` | `0.803740` | `3970900` | `969630` | `29049` |

## DRA Export

The completed full-coverage run directories were exported under:

```text
s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/
```

Export details:

- Temporary DRA: `dra-0b82228ada587f7ab`
- Export task: `task-07845dd08e72eec58`
- Export task result: `SUCCEEDED`
- Export task counts: `10463` total, `10463` succeeded, `0` failed
- Temporary DRA cleanup: detached after verification with `DeleteDataInFileSystem=False`
- Verified FSx/S3 manifest entries: `9029` on FSx and `9029` in S3
- Verified total bytes: `42814922525` on FSx and `42814922525` in S3
- Missing entries: `0`
- Extra entries: `0`
- Size mismatches: `0`

Manifest artifacts:

```text
s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/fsx_manifest.tsv
s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/s3_manifest.tsv
s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/verification_summary.json
```

The export was scoped to the three completed full-coverage workdirs because downsample workdirs were launched afterward and are actively changing under `/fsx/analysis_results/ubuntu/`.

## In Progress / To Be Produced: Downsample HIOMR Matrix

Downsample input files and manifests are already prepared:

```text
/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z
/fsx/analysis_results/johnm/staged_sample_data/hg003_altair_ont_hiomr_matrix_20260523T141028Z
```

All downsample HIOMR dry-runs have passed with rc `0`. The first real batch is running with no more than four concurrent workflows. The planned all-chromosome workdirs are:

| ILMN | ONT | Planned workdir | Status |
|---:|---:|---|---|
| 20x | 10x | `hg003a_altair3_hiomr_ilmn20x_ont10x_1021` | Real run in progress |
| 20x | 7x | `hg003a_altair3_hiomr_ilmn20x_ont7x_1021` | Real run in progress |
| 20x | 5x | `hg003a_altair3_hiomr_ilmn20x_ont5x_1021` | Real run in progress |
| 15x | 10x | `hg003a_altair3_hiomr_ilmn15x_ont10x_1021` | Real run in progress |
| 15x | 7x | `hg003a_altair3_hiomr_ilmn15x_ont7x_1021` | To be produced |
| 15x | 5x | `hg003a_altair3_hiomr_ilmn15x_ont5x_1021` | To be produced |
| 10x | 10x | `hg003a_altair3_hiomr_ilmn10x_ont10x_1021` | To be produced |
| 7x | 7x | `hg003a_altair3_hiomr_ilmn7x_ont7x_1021` | To be produced |
| 7x | 5x | `hg003a_altair3_hiomr_ilmn7x_ont5x_1021` | To be produced |
| 5x | 5x | `hg003a_altair3_hiomr_ilmn5x_ont5x_1021` | To be produced |

Each run will use DayOA `1.0.21`, `hg38_broad`, and:

```bash
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

The queue policy for the matrix is dry-runs first, then no more than four real workflows running at once.
