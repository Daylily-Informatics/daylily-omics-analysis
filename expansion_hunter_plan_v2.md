# ExpansionHunter v2 Multiagent Plan

## Goal
Add a first-class short-read ExpansionHunter workflow to `/Users/jmajor/projects/daylily/daylily-omics-analysis` for `sent`, `sentcg`, and `ug` alignments on `hg38` and `hg38_broad`.

The implementation must be concrete, testable locally on a Mac after `conda activate DAY-EC`, and acceptable on an AWS ParallelCluster headnode only through the supported `daylily-ec`/SSM path. Do not use SSH, PEM files, or `pcluster ssh`.

## Non-Negotiables
- Keep the runtime path direct. Do not add fallback catalogs, fallback sex defaults, fallback CRAM discovery, or silent best-effort behavior.
- Unknown or missing biological sex must fail before calling ExpansionHunter.
- `hg38` and `hg38_broad` both use the same vendored GRCh38 `chr` catalog unless a reviewer proves a contig-name mismatch.
- Do not make final WGS MultiQC always depend on ExpansionHunter. It can include ExpansionHunter custom content when the aggregate TSV exists.
- Remote commands that need PATH, conda, aliases, functions, Slurm, or Daylily setup must run in a login bash shell. Inside SSM/tmux, use separate commands for `source dyoainit`, `dy-a ...`, and `dy-r ...`.

## Shared Source Facts
- Existing workflow entrypoint: `workflow/Snakefile`.
- Existing rule directory: `workflow/rules/`.
- Existing conda env directory: `workflow/envs/`.
- Existing supporting-file configs:
  - `config/supporting_files/hg38_supporting_files.yaml`
  - `config/supporting_files/hg38_broad_supporting_files.yaml`
- Existing profile templates:
  - `config/day_profiles/local/templates/rule_config.yaml`
  - `config/day_profiles/slurm/templates/rule_config.yaml`
- Existing MultiQC config: `config/external_tools/multiqc_config.yaml`.
- Existing utility-script home: `bin/util/`.
- Existing tests:
  - `tests/test_workflow_catalog.py`
  - `tests/test_complete_genomics_sentieon.py`
  - `tests/test_giab_qc_contracts.py`
  - add `tests/test_expansionhunter_contracts.py`

## Proposed User-Facing Targets
- `produce_expansionhunter`: run per-sample ExpansionHunter and parse per-sample TSV outputs.
- `produce_expansionhunter_multiqc`: aggregate per-sample TSVs into a MultiQC-ready report.

Recommended dry-run command after activation:

```bash
source dyoainit
dy-a local hg38
dy-r produce_expansionhunter --config aligners=['sent','sentcg','ug'] dedupers=['dppl'] -p -j 1 -k -n
```

Recommended headnode dry-run command after SSM login and analysis checkout activation:

```bash
source dyoainit
dy-a slurm hg38_broad
dy-r produce_expansionhunter --config aligners=['sent','sentcg','ug'] dedupers=['dppl'] -p -j 100 -k -n
```

## Agent Ownership

### Agent 1: Plan Owner
Scope:
- Own this plan only: `expansion_hunter_plan_v2.md`.
- Coordinate assumptions, file ownership, and acceptance criteria.
- Do not edit implementation files.

Deliverables:
- This plan.
- Final synthesis of changed files and assumptions.

### Agent 2: Catalog and Config Owner
Allowed files:
- `resources/strchive/STRchive-disease-loci.hg38.stranger.json`
- `resources/strchive/README.md`
- `config/supporting_files/hg38_supporting_files.yaml`
- `config/supporting_files/hg38_broad_supporting_files.yaml`
- `config/day_profiles/local/templates/rule_config.yaml`
- `config/day_profiles/slurm/templates/rule_config.yaml`
- `workflow/envs/expansionhunter_v0.1.yaml`

Tasks:
1. Vendor STRchive v2.16.0 disease-loci catalog from `data/catalogs/STRchive-disease-loci.hg38.stranger.json`.
2. Add local attribution in `resources/strchive/README.md` with source URL, version tag, retrieval date, and license note.
3. Add a single supporting-files key for the catalog under both `hg38` and `hg38_broad`, for example `strchive_disease_loci_hg38_json`.
4. Add `expansionhunter` rule config to both profile templates.

Profile values:

```yaml
expansionhunter:
  env_yaml: "../envs/expansionhunter_v0.1.yaml"
  threads: 16
  mem_mb: 32000
  partition: "i192,i192mem,i128"
  analysis_mode: "seeking"
  region_extension_length: 1000
```

Local profile may reduce `threads` to `7` if consistent with nearby local rules, but it must keep the same keys.

Conda env requirements:

```yaml
name: expansionhunter_v0.1
channels:
  - conda-forge
  - bioconda
dependencies:
  - expansionhunter=5.0.0
  - htslib
  - python
  - samtools
```

Acceptance:
- Catalog JSON parses.
- Catalog contains required keys: `LocusId`, `ReferenceRegion`, `LocusStructure`, `NormalMax`, `PathologicMin`.
- Config references are exact repo-relative paths and do not reference network URLs.

### Agent 3: Snakemake Rule Owner
Allowed files:
- `workflow/Snakefile`
- `workflow/rules/expansionhunter.smk`

Tasks:
1. Include `workflow/rules/expansionhunter.smk` from `workflow/Snakefile`.
2. Add per-sample rule `expansionhunter` that consumes existing CRAM outputs:
   - `sent` and `sentcg`: deduped CRAM with non-`na` deduper, usually `dppl`.
   - `ug`: no-dedup normalized CRAM with `ddup='na'`.
3. Require CRAM index availability with the CRAM input. Do not auto-generate a fallback index path.
4. Pass these ExpansionHunter arguments:
   - `--reads`
   - `--reference`
   - `--variant-catalog`
   - `--output-prefix`
   - `--threads`
   - `--analysis-mode`
   - `--sex`
   - `--region-extension-length`
5. Write outputs under the aligned sample's existing result subtree:
   - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.json`
   - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.vcf`
   - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.bam`
   - `htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.tsv`
6. Use existing log and benchmark conventions under the same result subtree.
7. Add local target rule `produce_expansionhunter`.

Acceptance:
- `dy-r help` lists `produce_expansionhunter`.
- Rule text has all required ExpansionHunter CLI arguments.
- Dry-run fails loudly if sex is missing rather than substituting a value.
- Dry-run expands `sent`/`sentcg` deduped CRAMs and `ug/na` CRAMs where matching inputs exist.

### Agent 4: Parser and MultiQC Owner
Allowed files:
- `bin/util/parse_expansionhunter_json.py`
- `workflow/rules/expansionhunter.smk`
- `config/external_tools/multiqc_config.yaml`

Tasks:
1. Implement `bin/util/parse_expansionhunter_json.py`.
2. Inputs:
   - ExpansionHunter JSON
   - STRchive catalog JSON
   - sample
   - aligner
   - deduper
   - optional output path
3. Join STRchive annotations by `LocusId`.
4. Emit one row per locus or variant with stable TSV columns:
   - `sample`
   - `aligner`
   - `deduper`
   - `locus_id`
   - `variant_id`
   - `gene`
   - `disease`
   - `reference_region`
   - `locus_structure`
   - `repeat_unit`
   - `genotype`
   - `confidence_interval`
   - `coverage`
   - `normal_max`
   - `pathologic_min`
   - `status`
5. Status values must be exactly:
   - `normal`
   - `pathogenic_range`
   - `intermediate_or_uncertain`
   - `no_call`
6. Missing required JSON fields must raise a nonzero exit with a clear error.
7. Add aggregate rule and target `produce_expansionhunter_multiqc`.
8. Aggregate output:
   - `results/day/{genome_build}/other_reports/expansionhunter_mqc.tsv`
9. MultiQC custom-data config:
   - Add `expansionhunter` `custom_data`.
   - Add `sp` pattern for `other_reports/expansionhunter_mqc.tsv`.

Acceptance:
- Parser unit tests cover normal, pathogenic-range, uncertain, and no-call rows.
- Parser writes deterministic column order.
- MultiQC config recognizes the aggregate without forcing the final WGS target to depend on it.

### Agent 5: Tests and Local Verification Owner
Allowed files:
- `tests/test_expansionhunter_contracts.py`
- Existing tests only if the ExpansionHunter feature requires extending them:
  - `tests/test_workflow_catalog.py`
  - `tests/test_complete_genomics_sentieon.py`
  - `tests/test_giab_qc_contracts.py`

Tasks:
1. Add catalog contract tests:
   - Vendored catalog exists.
   - JSON parses.
   - Expected required keys are present.
   - `hg38` and `hg38_broad` supporting-files configs point to the vendored catalog.
2. Add workflow contract tests:
   - `workflow/Snakefile` includes `rules/expansionhunter.smk`.
   - Rule contains required CLI args.
   - Target names are present.
   - `sent` and `sentcg` use deduped CRAM paths.
   - `ug` uses `ddup='na'` CRAM paths.
3. Add parser tests with synthetic JSON and a minimal catalog.
4. Add MultiQC config tests.

Local verification command:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
python -m pytest -q tests/test_expansionhunter_contracts.py tests/test_workflow_catalog.py tests/test_complete_genomics_sentieon.py tests/test_giab_qc_contracts.py
ruff check bin/util/parse_expansionhunter_json.py tests/test_expansionhunter_contracts.py
git diff --check
```

Acceptance:
- All listed local checks pass.
- Any test that cannot run on macOS due to missing cluster data is contract-only and does not pretend to execute the workflow.

### Agent 6: Cluster Acceptance Owner
Allowed files:
- None unless a cluster-only issue is proven and reassigned by Agent 1.

Required inputs before any remote run:
- AWS profile. Do not use `default`; ask if missing.
- Region.
- Cluster name.
- Workset code for `day-clone -d`.
- Git ref for `day-clone -t`.
- Unique destination path or run-id workset. Do not reuse a shared destination.
- S3 paths for `config/samples.tsv` and `config/units.tsv`.
- Genome build, usually `hg38_broad`.

Mac connect prelude:

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
AWS_PROFILE=<profile> daylily-ec headnode connect --profile <profile> --region <region> --cluster <cluster>
```

Inside the SSM session:

```bash
id -un
echo "$0"
command -v day-clone
command -v tmux
command -v squeue
```

If the shell is not login bash, run:

```bash
exec bash -l
```

Persistent tmux launch skeleton:

```bash
tmux new-session -d -s <workset>_expansionhunter_<yyyymmdd>
tmux send-keys -t <session> 'cd /fsx/analysis_results/ubuntu' Enter
tmux send-keys -t <session> 'day-clone -t <git_ref> -d <workset_code>' Enter
tmux send-keys -t <session> 'cd /fsx/analysis_results/ubuntu/<workset_code>/daylily-omics-analysis' Enter
tmux send-keys -t <session> 'mkdir -p ./config' Enter
tmux send-keys -t <session> 'aws s3 cp <samples_s3_uri> ./config/samples.tsv' Enter
tmux send-keys -t <session> 'aws s3 cp <units_s3_uri> ./config/units.tsv' Enter
tmux send-keys -t <session> 'source dyoainit' Enter
tmux send-keys -t <session> 'dy-a slurm <genome_build>' Enter
tmux send-keys -t <session> "dy-r produce_expansionhunter --config aligners=['sent','sentcg','ug'] dedupers=['dppl'] -p -j 100 -k -n" Enter
```

Before interacting with an existing session:

```bash
window_count=$(tmux list-windows -t <session> -F '#{window_index}' | wc -l)
pane_count=$(tmux list-panes -a -F '#{session_name}' | awk '$1 == "<session>" {n++} END {print n + 0}')
test "$window_count" -eq 1
test "$pane_count" -eq 1
```

Acceptance checks after dry-run:

```bash
tmux capture-pane -pt <session> -S -160
squeue -u ubuntu | head -80
ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}' | head -40
```

Cluster acceptance criteria:
- `squeue` is on PATH. If not, status check fails.
- Dry-run DAG includes ExpansionHunter jobs for available `sent/dppl`, `sentcg/dppl`, and `ug/na` inputs.
- A one-sample real run produces JSON, VCF, BAMlet, parsed TSV, benchmark, aggregate TSV, and ExpansionHunter MultiQC HTML.
- Latest `.snakemake/log/<timestamp>` has no unresolved ExpansionHunter errors.
- Relevant `logs/slurm/expansionhunter/*.{out,err}` files show successful command execution.

## Merge Order
1. Agent 2 lands catalog, configs, and env.
2. Agent 3 lands Snakemake rule and target.
3. Agent 4 lands parser and MultiQC integration.
4. Agent 5 lands tests and local verification.
5. Agent 6 runs remote dry-run and one-sample real acceptance only after the branch is pushed and remote inputs are explicitly provided.

## Final Definition of Done
- Local contract/unit checks pass.
- `git diff --check` passes.
- `dy-r produce_expansionhunter ... -n` works locally as a DAG contract check where test inputs support it.
- Remote dry-run is completed through `daylily-ec`/SSM with a login bash shell.
- One-sample remote real run produces all expected ExpansionHunter artifacts.
- No unrelated files are edited.

## Strict Process Cleanup
- Capture `dy-r help` from the activated headnode checkout and verify the ExpansionHunter targets are visible.
- Push the implementation branch before the strict remote rerun so `day-clone -t <git_ref>` can clone the actual branch code instead of relying on a patch tarball.
- Stage `config/samples.tsv` and `config/units.tsv` to explicit S3 URIs, then copy those S3 manifests into the strict smoke workdir.
- Rerun the same three-platform smoke from a new unique workdir through `daylily-ec`/SSM and a login bash shell.
- Collect the dry-run DAG, real-run `WORKFLOW SUCCESS`, final artifact counts, aggregate TSV, focused MultiQC HTML, rule logs, and Slurm status evidence.

## Current Assumptions
- STRchive v2.16.0 disease-loci catalog is the intended disease-locus catalog.
- ExpansionHunter 5.0.0 from Bioconda is acceptable for the first implementation.
- `samples.tsv` has a usable sex field or can be extended explicitly; missing sex is a hard failure.
- `hg38_broad` uses GRCh38 `chr` contig names compatible with the STRchive hg38 catalog.
- Initial scope excludes REViewer image generation and ExpansionHunterDenovo.
