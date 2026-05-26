# ugrun CLI Contract

Ultima `ugrun` workflows are explicit run-QC surfaces for DayOA. They consume staged Ultima run metadata and emit parser-backed `_mqc.tsv` evidence for MultiQC and QEO.

The CLI contract is:

```bash
dy-r produce_ultima_run_qc -p -j 1
```

Inputs must be explicitly configured. Missing run directories, manifests, or required metric files fail hard. The target does not infer alternate run paths and does not produce R2 release decisions.

