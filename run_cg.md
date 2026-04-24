**Launch Sentieon Complete Genomics `sentcg` HG003 Run**

**Summary**
Run one fresh Complete Genomics HG003 workflow from a new tmux session using the new `sentcg` aligner path, downsampled inline from `units.tsv`, then `smd` dedup, then CG/MGI DNAscope (`cgt7p`). Use the pushed `complete-test` commit `4b46462`.

Default downsample value: `0.182`, because that is the value you previously asked to put in `units.tsv`. This is effectively the 30x target from the raw ~163x estimate.

**Key Changes In Effect**
- Use `aligners=[sentcg]`, not `sent`.
- `sentcg` alignment uses Sentieon BWA MEM with:
  - `DNAscopeMGIWGS2.1.bundle/bwa.model`
  - read group `PL:DNBSEQ`
  - inline `SUBSAMPLE_PCT` handling via the same `get_subsample_head/get_subsample_tail` pattern as the Illumina Sentieon rule
- Reuse existing dedup with `dedupers=[smd]`.
- Run CG/MGI DNAscope with:
  - `DNAscopeMGIWGS2.1.bundle/dnascope.model`
  - `--pcr_indel_model none`
- Use persistent results-tree scratch, not `/dev/shm`, for Sentieon sort and DNAscope scratch.

**Execution Plan**
1. On the headnode, create a new workset clone from `complete-test` at commit `4b46462`.
2. Copy the same single Complete Genomics HG003 `samples.tsv` and `units.tsv` used by the previous downsampled combo run.
3. Reduce `units.tsv` to the single Complete Genomics dataset row if needed.
4. Set `SUBSAMPLE_PCT=0.182` for that row.
5. Start a new tmux session, for example:
   - `cg_hg003_t7plus_sentcg_smd_cgt7p_ds0182_20260424`
6. Initialize one command at a time:
   - `source dyoainit`
   - `dy-a slurm hg38`
7. First dry-run:
   ```bash
   dy-r produce_alignstats produce_cgt7p_vcf produce_snv_concordances \
     -n -p -j 100 -k -T 1 \
     --retries 0 --rerun-incomplete --keep-incomplete \
     --config aligners=[sentcg] dedupers=[smd] snv_callers=[cgt7p]
   ```
8. If the dry-run resolves to `sentcg -> smd -> cgt7p`, launch the real run:
   ```bash
   dy-r produce_alignstats produce_cgt7p_vcf produce_snv_concordances \
     -p -j 100 -k -T 1 \
     --retries 0 --rerun-incomplete --keep-incomplete \
     --config aligners=[sentcg] dedupers=[smd] snv_callers=[cgt7p]
   ```

**Monitoring And Failure Policy**
- Verify tmux has exactly one window and one pane before interacting.
- Check `.snakemake/log`, latest `logs/slurm/**`, and stable rule logs on every check.
- Use `ssh <node> "bash -l -c '...'"` for compute-node inspection.
- Do not touch unrelated Slurm jobs.
- If this CG workflow fails:
  - inspect logs first
  - identify the concrete failure
  - patch the repo if needed
  - relaunch only after a fix
  - always relaunch with `--retries 0 --rerun-incomplete --keep-incomplete`

**Acceptance Criteria**
- `sentcg` alignment completes and produces `*.sentcg.sort.bam` plus `.bai`.
- `smd` dedup completes and produces `*.sentcg.smd.cram`, `.crai`, score, and metrics.
- `cgt7p` DNAscope completes and produces the final `*.sentcg.smd.cgt7p.snv.sort.vcf.gz` plus `.tbi`.
- `produce_snv_concordances` completes for the CG/MGI path.

**Assumptions**
- The requested “30x downsample float value” is `0.182`.
- Only `smd` dedup should run for this focused Sentieon CG workflow.
- The prior two-run/combo sessions should not be reused; this should be a fresh single-purpose tmux session and workset.
