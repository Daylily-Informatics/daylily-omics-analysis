# Workflow Visualizations

Daylily workflows are Snakemake workflows, so the standard graph and report features are available through `dy-r`.

## Rule Graph

```bash
dy-r produce_snv_concordances --rulegraph | dot -Tpng > rulegraph.png
```

The rule graph shows rule dependencies without expanding every file edge.

## File Graph

```bash
dy-r produce_snv_concordances --filegraph | dot -Tpng > filegraph.png
```

The file graph includes input/output relationships and can become large.

## DAG

```bash
dy-r produce_snv_concordances --dag | dot -Tpng > dag.png
```

The full DAG can become difficult to inspect for large sample tables or caller grids.

## Snakemake Report

After a run completes:

```bash
dy-r produce_snv_concordances --report ./smk_report.html
```

Daylily aggregate QC reports are produced by workflow targets such as
`produce_multiqc_all` and by rule-specific report compilers under
`results/day/<build>/other_reports/`. The older `produce_multiqc_final_wgs`
target remains available as a deprecated compatibility alias.
