# Analysis Manifest (Legacy)

> **Note:** Daylily now expects separate `config/samples.tsv` and `config/units.tsv` files that together replace the old `analysis_manifest.csv`. The information below is retained for historical reference when converting legacy manifests into the new tables.

- This is the legacy 'sample sheet' required to run earlier versions of Daylily.  The modern equivalents are `.samples.tsv`/`.units.tsv` pairs such as [this HG002 smoke test](../../.test_data/data/0.01xwgs_HG002_hg38.samples.tsv).
- Historical 7-sample GIAB examples may still exist in older run branches or archived worksets; current example tables live under `.test_data/data/`.
- Legacy workflows copied the manifest to `config/analysis_manifest.csv`. Modern workflows should copy both tables to `config/samples.tsv` and `config/units.tsv`.
- Current inline FASTQ downsampling belongs in `config/units.tsv` as `SUBSAMPLE_PCT`, a float in `(0.0, 1.0]`.
- If specified, truth VCF and BED files will be auto-detected and create concordance analysis reports.
