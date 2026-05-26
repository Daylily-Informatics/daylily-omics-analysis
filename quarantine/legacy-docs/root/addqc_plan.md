# 8-Agent GIAB 5x Pipeline And QC Debug Plan

## Summary
- Use 8 coordinated agents against one branch: `codex/giab7-5x-qc-debug`.
- Use the already installed local `DAY-EC` `daylily-ec`; do not install or upgrade it.
- Target cluster: `mk-gotime3`, profile `daylily-service-lsmc`, region `us-west-2`.
- Remote workset: `giab7_ilmn5x_qc_20260425`; tmux session: `giab7_ilmn5x_qc_20260425`.
- Primary command, dry-run first then real:
  `dy-r produce_snv_concordances produce_alignstats produce_multiqc_final_wgs --config aligners=['sent'] dedupers=['dppl'] snv_callers=['sentd'] -p -j 100 -k`

## Agent Assignments
- Agent 1, Orchestrator: owns branch creation, `daylily-ec` connection, remote clone, tmux launch, queue monitoring, and final evidence bundle. It never edits workflow code.
- Agent 2, Manifest Runner: owns GIAB HG001-HG007 `samples.tsv`/`units.tsv` generation, validates `/fsx/references/.../HG00*_30x_R{1,2}.fastq.gz`, sets `SUBSAMPLE_PCT=0.1666666667`, and verifies dry-run DAG shape.
- Agent 3, Core Pipeline Debugger: owns failures in alignment, Doppelmark/dedup, Sentieon DNAscope, concordance, alignstats, and MultiQC completion.
- Agent 4, Peddy Debugger: owns `workflow/rules/peddy.smk`; fixes masked failures so peddy exits hard and `.done` files are created only after expected outputs exist.
- Agent 5, Contamination Debugger: owns `workflow/rules/gatk_contam.smk` and `workflow/rules/verifybamid2_contam.smk`; fixes target expansion/path mismatches and validates GATK plus VerifyBamID2 outputs.
- Agent 6, Synthetic Contamination Agent: owns reusable HG002+HG003 contamination FASTQ generation under `/fsx/scratch/dayoa_qc_contam/giab_hg002_hg003_5x_20260425/` for 0.1, 0.5, 1, 2, 3, 4, 5, 10, 20, and 30 percent contamination.
- Agent 7, Relatedness Agent: owns a Somalier-first relationship tool design and implementation, using a manifest-driven pairwise classifier for duplicate, parent-child, sibling/first-degree, unrelated, and ambiguous pairs.
- Agent 8, Verification Agent: owns tests, dry-runs, output audits, and regression checks; it does not change production rules except test fixtures.

## Coordination Rules
- One agent owns each file before editing; no overlapping edits without Orchestrator approval.
- Agents 4, 5, 6, and 7 work on disjoint file sets and can proceed in parallel after Agent 2 validates manifests.
- Orchestrator merges code locally, pushes the branch, and refreshes the headnode clone before reruns.
- Debug order is always newest Snakemake master log, then `logs/slurm/<rule>/*.{out,err}`, then stable rule logs under `results/day/<build>/...`.
- No destructive AWS actions. Do not cancel unrelated Slurm jobs.

## Acceptance Criteria
- 7-sample GIAB run completes on `hg38_broad`.
- Outputs exist for all 7 samples: sent alignment, dmd/dppl-normalized dedup CRAM+CRAI, sentd VCF+TBI, concordance, alignstats, peddy, GATK contamination, VerifyBamID2 contamination, and final MultiQC HTML.
- Synthetic contamination FASTQs, manifests, and observed-vs-expected summary TSV are preserved under `/fsx/scratch/dayoa_qc_contam/...`.
- Relatedness tool produces cached fingerprints, pairwise matrix, classified relationship summary, and HTML/TSV report.
- Tests cover manifest validation, peddy hard failures, contamination target expansion, synthetic contamination manifest generation, relationship classification, and dry-run DAGs.

## Assumptions
- Use a new dev branch, not headnode-only patching.
- Use HG002 as primary and HG003 as donor for synthetic contamination.
- Relationship tool should classify all pairs first, with optional declared-expectation validation.
- `produce_multiqc_final_wgs` is the actual target name; treat `produce_multiqc_final` as a user-facing shorthand.
