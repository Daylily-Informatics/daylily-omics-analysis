# ExpansionHunter Short-Read STR Rule

## Summary
Add an ExpansionHunter workflow for short-read Illumina (`sent`), Complete Genomics/MGI (`sentcg`), and Ultima (`ug`) data on `hg38` and `hg38_broad`. The rule will use the tagged STRchive v2.16.0 disease-loci catalog, produce raw ExpansionHunter outputs, parse a locus-level TSV, and expose a MultiQC-ready aggregate.

Sources: [STRchive catalog](https://github.com/dashnowlab/STRchive/blob/v2.16.0/data/catalogs/STRchive-disease-loci.hg38.stranger.json), [ExpansionHunter usage](https://github.com/Illumina/ExpansionHunter/blob/master/docs/03_Usage.md), [ExpansionHunter JSON output](https://github.com/Illumina/ExpansionHunter/blob/master/docs/05_OutputJsonFiles.md), [ExpansionHunter VCF output](https://github.com/Illumina/ExpansionHunter/blob/master/docs/06_OutputVcfFiles.md), [Bioconda package](https://bioconda.github.io/recipes/expansionhunter/README.html).

## Key Changes
- Vendor `STRchive-disease-loci.hg38.stranger.json` under repo resources with attribution/license metadata; point both `hg38` and `hg38_broad` supporting-files configs at the same catalog because both use GRCh38 `chr` coordinates.
- Add `workflow/rules/expansionhunter.smk` and include it from `workflow/Snakefile`.
- Add rule config to local and slurm profile templates:
  - `env_yaml: "../envs/expansionhunter_v0.1.yaml"`
  - `threads: 16`, `mem_mb: 32000`, `partition: "i192,i192mem,i128"`
  - `analysis_mode: "seeking"`, `region_extension_length: 1000`
  - `min_locus_coverage: 10` is superseded/invalid for ExpansionHunter 5.0.0. The cluster-installed EH 5.0.0 CLI does not accept `--min-locus-coverage`; passing it aborts the command. The implemented rule intentionally omits that flag and keeps `extra_args` for future supported EH arguments.
- Add `workflow/envs/expansionhunter_v0.1.yaml` with `expansionhunter=5.0.0` from Bioconda plus `python`, `samtools`, and `htslib`.
- Add target `produce_expansionhunter`:
  - For `sent` and `sentcg`, consume `{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram` and require a non-`na` deduper such as `dedupers=['dppl']`.
  - For `ug`, consume normalized no-dedup CRAM output with `ddup='na'`.
  - Recommended command: `dy-r produce_expansionhunter --config aligners=['sent','sentcg','ug'] dedupers=['dppl'] -p -j 100 -k -n`.
- Per sample/alnr/ddup output location:
  - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.json`
  - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.vcf`
  - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.bam`
  - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.tsv`
  - logs and benchmark under the existing log/benchmark conventions.
- Add parser utility for ExpansionHunter JSON:
  - Join STRchive annotations by `LocusId`.
  - Emit one TSV row per locus/variant with sample, aligner, deduper, gene, disease, reference region, repeat unit, genotype, confidence interval, coverage, normal/pathologic thresholds, and interpreted status.
  - Status values: `normal`, `pathogenic_range`, `intermediate_or_uncertain`, `no_call`.
- Add `produce_expansionhunter_multiqc`:
  - Gather per-sample TSVs into `other_reports/expansionhunter_mqc.tsv`.
  - Add `expansionhunter` `custom_data` and `sp` entries to `config/external_tools/multiqc_config.yaml`.
  - Produce an ExpansionHunter-focused MultiQC HTML without making final WGS MultiQC always depend on ExpansionHunter.

## Test Plan
- Static contract tests:
  - STRchive catalog is vendored, valid JSON, has 74 loci, and includes required keys such as `LocusId`, `ReferenceRegion`, `LocusStructure`, `NormalMax`, and `PathologicMin`.
  - `hg38` and `hg38_broad` supporting-files configs point to the vendored catalog.
  - Snakefile includes the new ExpansionHunter rule file.
  - Rule text includes `ExpansionHunter --reads`, `--reference`, `--variant-catalog`, `--output-prefix`, `--threads`, and `--analysis-mode`.
- Parser unit tests:
  - Synthetic EH JSON plus mini STRchive catalog yields stable TSV columns.
  - Normal, pathogenic-range, uncertain, and no-call rows are classified correctly.
  - Missing required JSON fields fail loudly with a useful error.
- Workflow tests:
  - Add tests proving `sent` and `sentcg` use deduped CRAM paths and `ug` uses `na` CRAM paths.
  - Add tests proving the MultiQC config contains the new custom-data section and `sp` file pattern.
  - Run `python -m pytest -q tests/test_giab_qc_contracts.py tests/test_complete_genomics_sentieon.py tests/test_workflow_catalog.py tests/test_expansionhunter_contracts.py`.
  - Run `ruff check` on new Python parser/tests and `git diff --check`.
- Remote dry-run acceptance:
  - On headnode, run `dy-r produce_expansionhunter --config aligners=['sent','sentcg','ug'] dedupers=['dppl'] -p -j 100 -k -n`.
  - Confirm DAG includes ExpansionHunter jobs for `sent/dmd`, `sentcg/dmd`, and `ug/na` where those inputs are present.
  - Run a small real sample and confirm JSON, VCF, BAMlet, TSV, benchmark, aggregate TSV, and MultiQC HTML are produced.

## Assumptions
- `hg38_broad` uses the same STRchive hg38 catalog because the reference has GRCh38 `chr` contig naming compatible with the catalog.
- Unknown biological sex should fail for this target rather than silently defaulting, because ExpansionHunter sex affects chrX/chrY loci.
- Initial output is disease-loci reporting only; no REViewer image generation or ExpansionHunterDenovo is included.
- Final WGS MultiQC will include ExpansionHunter custom content when the aggregate TSV exists, but it will not force ExpansionHunter as a dependency for every final-report run.
