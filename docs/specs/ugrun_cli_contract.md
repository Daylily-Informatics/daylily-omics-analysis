# ugrun CLI Contract

Ultima `ugrun` workflows are explicit run-QC surfaces for DayOA. They consume staged Ultima run metadata and emit parser-backed `_mqc.tsv` evidence for MultiQC and QEO.

The CLI contract is:

```bash
dy-r produce_ultima_run_qc -p -j 1
```

Inputs must be explicitly configured. Missing run directories, manifests, required metric files, or expected demux FASTQs fail hard. The target does not infer alternate run paths and does not produce R2 release decisions.

For mounted run contexts, `produce_ultima_run_qc` includes demux FASTQ QC. The demux QC rules scan the explicit `RUN_DIR`, group FASTQs by containing directory, derive collision-checked identifiers from `RUNID` plus the group path relative to `RUN_DIR`, run FastQC and SeqKit, and build a focused MultiQC report under `run_qc/ultima/`.
