# Ultima Run QC Workflow

Ultima run QC is an explicit parser-backed run-QC workflow. It is not part of routine final MultiQC unless the operator targets it or enables the relevant run-QC surface. For mounted run contexts, `produce_ultima_run_qc` also runs demux FASTQ QC once demultiplexed FASTQs are present under `RUN_DIR`.

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
source dyoainit
dy-a local hg38
dy-r produce_ultima_run_qc -n -p -j 1
```

The demux FASTQ QC path scans `RUN_DIR` for `*.fastq.gz` and `*.fq.gz`, groups files by containing directory, derives collision-checked sample identifiers from the run id plus the group path relative to `RUN_DIR`, symlinks FASTQs into group-local FastQC inputs, runs FastQC and SeqKit, and builds `ultima_demux_fastq.multiqc.html`.

Outputs are `_mqc.tsv` evidence tables, demux FastQC/SeqKit outputs, focused MultiQC HTML, and supporting logs. DayOA does not turn Ultima run QC into a clinical release decision.
