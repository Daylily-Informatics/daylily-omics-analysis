# Running the Bundled Smoke Test

Daylily ships with bundled 0.01x HG002 input tables for a minimal operator test.
Stage those tables into `config/`, then run a small target in `local` mode.

```bash
# from the cloned repository root

. dyoainit
dy-a local hg38

cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r produce_alignstats -p -j 1 -n
dy-r produce_alignstats -p -j 1
```

If you only want a validation pass, stop after the dry-run command.
