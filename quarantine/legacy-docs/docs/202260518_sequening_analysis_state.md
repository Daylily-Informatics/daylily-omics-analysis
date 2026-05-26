# Sequencing Analysis State - 2026-05-18

CloudFront report URLs below use the shared LSMC QC Basic Auth credentials. Username: `lsmc-qc-curious`. The password was shared separately and is not stored in this document.

## Sequencing Run QC

### Run QC Reports

| Scope | Status | URL |
| --- | --- | --- |
| Illumina run QC, all runs | In development | https://dlqovrcm5y71h.cloudfront.net/analysis_results/jem-scratch/run_qc_illumina_all/illumina_runs.multiqc.html |
| ONT run QC, all runs | In development | https://dlqovrcm5y71h.cloudfront.net/analysis_results/ubuntu/run_qc_ont_all/ont_runs.multiqc.html |
| Ultima run QC, all runs | No public tool yet | Pending |

### Run State Summary

| Platform | `<transferring>` | `<in progress>` | `<demuxed>` | `<Aligned>` | `<QC complete>` | `<Exception>` | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ultima | 0 | 0 | 5 | 3 | 1 | 1 | 10 |
| Illumina | 0 | 1 | 1 | 1 | 0 | 2 | 5 |
| ONT | 0 | 0 | 0 | 0 | 3 | 0 | 3 |

### Illumina Source Run QC

| Run | Raw sequence data S3 URI | Demux summary |
| --- | --- | --- |
| `LH01106_06MAR2026_PhiX_140pm_A` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260306_LH01106_0001_A23KV7KLT4/` | Demux stats are present and show `100.0000%` called reads with `0` undetermined reads. No BCLConvert quality metrics or fastq-list report artifacts were found in the checked S3 paths. |
| `LH01106_06MAR2026_PhiX_140pm_B` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260306_LH01106_0002_B23KV37LT4/` | Demux stats are present and show `100.0000%` called reads with `0` undetermined reads. No BCLConvert quality metrics or fastq-list report artifacts were found in the checked S3 paths. |
| `20260324_ILMN_training_instr_val` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260324_LH01106_0003_B23KV2VLT4/` | A SampleSheet and `CopyComplete.txt` are present, but no demux stats, BCLConvert quality metrics, or fastq-list artifacts were found in the checked S3 paths. |
| `20260407_ILMN_training_instr_val_2` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260407_LH01106_0004_A23K5LJLT4/` | A SampleSheet and `CopyComplete.txt` are present, but no demux stats, BCLConvert quality metrics, or fastq-list artifacts were found in the checked S3 paths. |
| `20260507_23andMe_run-1` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260507_LH01106_0005_A23K3JVLT4/` | BCLConvert report artifacts exist for `96` samples across `8` lanes with `93.3175%` Q30. No `Demultiplex_Stats.csv` or unknown-barcode demux stats were found in the checked S3 paths. |
| `20260512_ILMN_Altair_Run_1` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260512_LH01106_0006_A23K3H2LT4/` | Demux completed and is usable: `85.6783%` called reads, `14.3217%` undetermined reads, all `41` SampleSheet samples nonzero, and `92.9441%` Q30. The largest top-unknown barcode entry is small relative to total reads. |
| `20260512_ILMN_Altair_Run_2` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260512_LH01106_0007_B23K5JKLT4/` | Demux artifacts are present, but demux effectively failed: only `8` called reads total, with `33,436,817,267` reads undetermined, despite `93.3194%` Q30. The top 8,000 unknown barcode pairs did not match this run's SampleSheet expected pairs or individual index sequences in the prior check. |
| `20260514_23andMe_run-2` | `s3://lsmc-ssf-sequencing-data/raw/lsmc/ssf-hq/LH01106/2026/20260514_LH01106_0008_A23TVNWLT4/` | Transfer marker `OOW.done` is present in the raw S3 prefix, but no demux stats, BCLConvert quality metrics, or fastq-list artifacts were found there. This appears to be raw source data only in the checked prefix. |
| `20260514_ILMN_Altair_Run_3` | `s3://lsmc-ssf-sequencing-data/raw/lsmc/ssf-hq/LH01106/2026/20260514_LH01106_0009_B23TVLGLT4/` | Demux artifacts are present and look usable: `87.0563%` called reads, `12.9437%` undetermined reads, all `41` SampleSheet samples nonzero, and `94.3353%` Q30. Caveat: the raw S3 prefix currently has `OOW.err`, so the S3 transfer state is not clean even though demux CSVs are present. |

## Run Analysis

### Ultima

#### `504632-20260326_2146` `<demuxed>`

- Run Name: `504632-20260326_2146` `<demuxed>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN504632/2026/504632-20260326_2146/`
- Results S3: pending; no DayOA analysis result directory was found in the checked analysis prefixes.
- Alignstats data: pending.
- MultiQC report: pending.

#### `505069-20260326_1848` `<demuxed>`

- Run Name: `505069-20260326_1848` `<demuxed>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN505069/2026/505069-20260326_1848/`
- Results S3: pending; no DayOA analysis result directory was found in the checked analysis prefixes.
- Alignstats data: pending.
- MultiQC report: pending.

#### `504970-20260331_1722` `<Aligned>`

- Run Name: `504970-20260331_1722` `<Aligned>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN504970/2026/504970-20260331_1722/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-504970-20260331-1722-20260425T091209Z/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-504970-20260331-1722-20260425T091209Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_gs_mqc.tsv`
- MultiQC report: pending; no `DAY_final_multiqc.html` was found in the checked results report directory.

#### `505064-20260331_2020` `<Aligned>`

- Run Name: `505064-20260331_2020` `<Aligned>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN505064/2026/505064-20260331_2020/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-505064-20260331-2020-20260425T090724Z/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-505064-20260331-2020-20260425T090724Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_gs_mqc.tsv`
- MultiQC report: pending; no `DAY_final_multiqc.html` was found in the checked results report directory.

#### `505451-20260402_1931` `<demuxed>`

- Run Name: `505451-20260402_1931` `<demuxed>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN505451/2026/505451-20260402_1931/`
- Results S3: pending; no DayOA analysis result directory was found in the checked analysis prefixes.
- Alignstats data: pending.
- MultiQC report: pending.

#### `505799-20260403_1500` `<demuxed>`

- Run Name: `505799-20260403_1500` `<demuxed>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN505799/2026/505799-20260403_1500/`
- Results S3: pending; no DayOA analysis result directory was found in the checked analysis prefixes.
- Alignstats data: pending.
- MultiQC report: pending.

#### `504352-20260404_1215` `<demuxed>`

- Run Name: `504352-20260404_1215` `<demuxed>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN504352/2026/504352-20260404_1215/`
- Results S3: pending; no DayOA analysis result directory was found in the checked analysis prefixes.
- Alignstats data: pending.
- MultiQC report: pending.

#### `602220-20260417_2047` `<Aligned>`

- Run Name: `602220-20260417_2047` `<Aligned>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN602220/2026/602220-20260417_2047/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-602220-20260417-2047-20260425T091209Z/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-602220-20260417-2047-20260425T091209Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_gs_mqc.tsv`
- MultiQC report: pending; no `DAY_final_multiqc.html` was found in the checked results report directory.

#### `602221-20260417_2346` `<Exception>`

- Run Name: `602221-20260417_2346` `<Exception>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN602221/2026/602221-20260417_2346/`
- **Source-data issue:** current dashboard inventory reports S3 has `1,977,460,351,578` bytes versus `2,123,313,589,081` bytes on SeqNAS, so treat this source prefix as partial until reconciled.
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-602221-20260417-2346-20260425T090724Z/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260421T065118Z/analysis_results/ubuntu/prod-alignstats-602221-20260417-2346-20260425T090724Z/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_gs_mqc.tsv`
- MultiQC report: pending; no `DAY_final_multiqc.html` was found in the checked results report directory.

#### `602202-20260512_1805` `<QC complete>`

- Run Name: `602202-20260512_1805` `<QC complete>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN602202/2026/602202-20260512_1805/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260515T103052Z/analysis_results/ubuntu/ultima_602202_20260512_1805_ksink105_20260517T190121Z/daylily-omics-analysis/results/day/hg38/`
- Alignstats data: https://dlqovrcm5y71h.cloudfront.net/ultima_602202_20260512_1805_ksink105_20260517T190121Z/daylily-omics-analysis/results/day/hg38/other_reports/alignstats_gs_mqc.tsv
- MultiQC report: https://dlqovrcm5y71h.cloudfront.net/ultima_602202_20260512_1805_ksink105_20260517T190121Z/daylily-omics-analysis/results/day/hg38/reports/DAY_final_multiqc.html

### Illumina

#### `20260507_23andMe_run-1` (`0005`) `<demuxed>`

- Run Name: `20260507_23andMe_run-1` `<demuxed>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260507_LH01106_0005_A23K3JVLT4/`
- SampleSheet check: root `SampleSheet.csv` has `RunName=20260507_23andMe_run-1`, which agrees with this section title for the `20260507_LH01106_0005_A23K3JVLT4` source directory.
- Demux note: BCLConvert report artifacts exist with `93.3175%` Q30, but no demux stats file was found in the checked S3 paths.
- Results S3: pending; combined-FQ-by-lane run in process.
- Alignstats data: pending; combined-FQ-by-lane run in process.
- MultiQC report: pending; combined-FQ-by-lane run in process.

#### `20260512_ILMN_Altair_Run_1` (`0006`) `<Aligned>`

- Run Name: `20260512_ILMN_Altair_Run_1` `<Aligned>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260512_LH01106_0006_A23K3H2LT4/`
- SampleSheet check: root `SampleSheet.csv` has `RunName=20260512_ILMN_Altair_Run_1`, which agrees with this section title for the `20260512_LH01106_0006_A23K3H2LT4` source directory.
- Demux note: Demux completed and is usable: `85.6783%` called reads, `14.3217%` undetermined reads, all `41` samples nonzero, and `92.9441%` Q30.
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260515T103052Z/analysis_results/ubuntu/ilmn_0006_align_dedup_alignstats_20260517T185626Z/daylily-omics-analysis/results/day/hg38/`
- Alignstats data: https://dlqovrcm5y71h.cloudfront.net/ilmn_0006_align_dedup_alignstats_20260517T185626Z/daylily-omics-analysis/results/day/hg38/other_reports/alignstats_combo_mqc.tsv
- MultiQC report: pending; combined-FQ-by-lane run in process.

#### `20260512_ILMN_Altair_Run_2` (`0007`) `<Exception>`

- Run Name: `20260512_ILMN_Altair_Run_2` `<Exception>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/LH01106/2026/20260512_LH01106_0007_B23K5JKLT4/`
- SampleSheet check: root `SampleSheet.csv` has `RunName=20260512_ILMN_Altair_Run_2`, which agrees with this section title for the `20260512_LH01106_0007_B23K5JKLT4` source directory.
- Demux note: Demux artifacts are present, but demux effectively failed: only `8` called reads total and almost all reads undetermined despite good sequencing quality. The observed unknown index population does not match the SampleSheet.
- Results S3: pending because of the index/demux issue.
- Alignstats data: pending.
- MultiQC report: pending.

#### `20260514_23andMe_run-2` (`0008`) `<in progress>`

- Run Name: `20260514_23andMe_run-2` `<in progress>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/raw/lsmc/ssf-hq/LH01106/2026/20260514_LH01106_0008_A23TVNWLT4/`
- SampleSheet check: root `SampleSheet.csv` has `RunName=20260514_23andMe_run-2`, which agrees with this section title for the `20260514_LH01106_0008_A23TVNWLT4` source directory.
- Demux note: The raw S3 prefix has `OOW.done`, but no demux stats or BCLConvert report CSVs were found in the checked raw prefix.
- Results S3: in progress.
- Alignstats data: in progress.
- MultiQC report: in progress.

#### `20260514_ILMN_Altair_Run_3` (`0009`) `<Exception>`

- Run Name: `20260514_ILMN_Altair_Run_3` `<Exception>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/raw/lsmc/ssf-hq/LH01106/2026/20260514_LH01106_0009_B23TVLGLT4/`
- SampleSheet check: root `SampleSheet.csv` has `RunName=20260514_ILMN_Altair_Run_3`, which agrees with this section title for the `20260514_LH01106_0009_B23TVLGLT4` source directory.
- Demux note: Demux artifacts are present and look usable: `87.0563%` called reads, `12.9437%` undetermined reads, all `41` samples nonzero, and `94.3353%` Q30. The raw S3 prefix currently has `OOW.err`, so the transfer state should be treated as incomplete or failed until that marker is resolved.
- Results S3: pending.
- Alignstats data: pending.
- MultiQC report: pending.

### ONT

#### `20260424_ONT_100ul` `<QC complete>`

- Run Name: `20260424_ONT_100ul` `<QC complete>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/pca100/2026/20260424_ONT_100ul/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260503T104054Z/analysis_results/ubuntu/pca100_ont_at_sanity_20260504/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260503T104054Z/analysis_results/ubuntu/pca100_ont_at_sanity_20260504/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_combo_mqc.tsv`
- MultiQC report: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260503T104054Z/analysis_results/ubuntu/pca100_ont_at_sanity_20260504/daylily-omics-analysis/results/day/hg38_broad/reports/DAY_final_multiqc.html`
- Analysis note: this April ONT result directory includes both `20260424_ONT_100ul` and `20260427_ONT_300ul`.

#### `20260427_ONT_300ul` `<QC complete>`

- Run Name: `20260427_ONT_300ul` `<QC complete>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/pca100/2026/20260427_ONT_300ul/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260503T104054Z/analysis_results/ubuntu/pca100_ont_at_sanity_20260504/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260503T104054Z/analysis_results/ubuntu/pca100_ont_at_sanity_20260504/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_combo_mqc.tsv`
- MultiQC report: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260503T104054Z/analysis_results/ubuntu/pca100_ont_at_sanity_20260504/daylily-omics-analysis/results/day/hg38_broad/reports/DAY_final_multiqc.html`
- Analysis note: this April ONT result directory includes both `20260424_ONT_100ul` and `20260427_ONT_300ul`.

#### `20260513_ONT_HG003` `<QC complete>`

- Run Name: `20260513_ONT_HG003` `<QC complete>`
- Raw data S3: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/pca100/2026/20260513_ONT_HG003/`
- Results S3: `s3://lsmc-dayoa-omics-analysis-us-west-2/FSxLustre20260515T103052Z/analysis_results/ubuntu/pca100_ont_hg003_20260513_kitchen_bc17_unclassified_dryrun2/daylily-omics-analysis/results/day/hg38_broad/`
- Alignstats data: https://dlqovrcm5y71h.cloudfront.net/pca100_ont_hg003_20260513_kitchen_bc17_unclassified_dryrun2/daylily-omics-analysis/results/day/hg38_broad/other_reports/alignstats_combo_mqc.tsv
- MultiQC report: https://dlqovrcm5y71h.cloudfront.net/pca100_ont_hg003_20260513_kitchen_bc17_unclassified_dryrun2/daylily-omics-analysis/results/day/hg38_broad/reports/DAY_final_multiqc.html

## Sample Analysis

### Hybrid ILMN+ONT

#### HG003

`<coming soon>`
