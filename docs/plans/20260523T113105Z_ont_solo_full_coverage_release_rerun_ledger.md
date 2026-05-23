# ONT Solo Full-Coverage Release And Rerun Ledger

## Summary

Release the minimal DayOA changes needed for the successful full-coverage HG003 ONT solo run, tag a new version, then launch a fresh `day-clone -t <tag>` ONT solo run with alignstats and corrected HG003 concordance manifest paths.

## Gate 0 Inventory

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `main`
- Remote: `origin git@github.com:Daylily-Informatics/daylily-omics-analysis.git`
- Baseline dirty files before release edits: `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk`, `workflow/rules/sent_hybrid_ilmn_ont_modular.smk`
- Latest existing release tag: `1.0.18`
- Successful diagnostic run: `hg003a_ont_snv_alignstats_1018_191_retain_tmp_v4`, `exit_code=0`, completed `2026-05-23T11:22:59Z`
- Successful ONT evidence: `sentieon-cli exit code: 0`, elapsed 11 minutes on `m7i.metal-48xl`, Slurm queue empty after completion
- Concordance skip root cause: staged `samples.tsv` points at `/data/staged_sample_data/.../concordance_data`, which is missing; actual staged truth data exists at `/fsx/data/staged_sample_data/.../concordance_data`
- No destructive AWS actions authorized or required.

## Rows

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| SRC-001 | DayOA source | Lower Slurm ONT `sentdont` full-coverage thread request to the successful 191-thread setting. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `config/day_profiles/slurm/templates/rule_config.yaml` now sets `sentdont.threads=191`, `sentdont.use_threads=191`; successful live run used the same values. | | Source config updated. |
| SRC-002 | Hybrid diagnostics | Preserve explicit hybrid-select environment logging for `hiom` and `hiomr` debugging without changing import behavior. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/sent_hybrid_ilmn_ont_modular.smk` and `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk` log `PATH`, `CONDA_PREFIX`, `which python`, `sys.executable`, `importlib_resources`, and resolved `hybrid_select.py`; the original `from importlib_resources import files` command remains unchanged. | | Diagnostic logging added without stdlib fallback or import rewrite. |
| MANIFEST-001 | HG003 manifests | Fix fresh-run HG003 `samples.tsv` concordance paths to `/fsx/data/staged_sample_data/.../concordance_data` and keep positive-control fields set. | OPEN | config_or_startup_contract | Gate 2 | orchestrator | Staged sample row has `IS_POSITIVE_CONTROL=true`, `EXTERNAL_SAMPLE_ID=HG003`, `TRUTH_DATA_DIR=/data/...`; `/data/...` missing, `/fsx/data/...` exists with HG003 VCF/BED ROI subdirs. | | |
| REL-001 | Release | Commit, push, tag next non-`v` semver version, and push tag. | IN_PROGRESS | feature_implementation | Gate 5 | orchestrator | Existing tags include `1.0.18`; next planned tag is `1.0.19`; validation: `git diff --check` clean, `pytest -q tests/test_slurm_profile.py tests/test_snakemake_parser_contracts.py tests/test_workflow_target_aliases.py` -> 8 passed. | | |
| RUN-001 | Fresh ONT run | Launch fresh `day-clone -t <new tag>` full-coverage ONT solo run including alignstats and concordance using corrected manifests. | OPEN | feature_implementation | Gate 5 | orchestrator | Run must use staged HG003 data; target command should include `produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances`; debug dry-run first. | | |
| HIOMR-001 | Hybrid follow-up | Report current `hiomr` target alias and defer focused debug until ONT release/rerun is launched. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Target alias used was `produce_sentdhiomr_snv_vcf`; failing downstream rule was `sentdhiomr_hybrid_select`. | | User asked which `sentdhiomr` rule was specified; answer provided in chat. |
