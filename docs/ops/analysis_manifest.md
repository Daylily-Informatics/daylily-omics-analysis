# Analysis Manifest (Legacy)

> **Note:** Daylily now expects separate `config/samples.tsv` and `config/units.tsv` files that together replace the old `analysis_manifest.csv`. The information below is retained for historical reference when converting legacy manifests into the new tables.

- This is the legacy 'sample sheet' required to run earlier versions of Daylily.  The modern equivalents are `.samples.tsv`/`.units.tsv` pairs such as [this HG002 smoke test](../../.test_data/data/0.01xwgs_HG002_hg38.samples.tsv).
- Another example which runs the 7 GIAB google-brain 30x dataset can be found [here](giab_30x_b37_analysis_manifest.samples.tsv) alongside its companion units table.
- Legacy workflows copied the manifest to `config/analysis_manifest.csv`. Modern workflows should copy both tables to `config/samples.tsv` and `config/units.tsv`.
- Optional column headers allow for sub sampling the input fastqs, as well as setting the `-k` bwa flag.
- If specified, truth VCF and BED files will be auto-detected and create concordance analysis reports.
