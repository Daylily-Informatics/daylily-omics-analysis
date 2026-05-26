# Ultima Run QC Workflow

Ultima run QC is an explicit parser-backed run-QC workflow. It is not part of routine final MultiQC unless the operator targets it or enables the relevant run-QC surface.

```bash
eval "$(conda shell.zsh hook)" && conda activate DAY-EC
source dyoainit
dy-a local hg38
dy-r produce_ultima_run_qc -n -p -j 1
```

Outputs are `_mqc.tsv` evidence tables and supporting logs. DayOA does not turn Ultima run QC into a clinical release decision.

