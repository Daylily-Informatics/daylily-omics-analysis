# Ultima Run QC Requirements

Ultima run QC in DayOA produces evidence for operational review and MultiQC/QEO observation. It must not create clinical release decisions or replace R2 interpretation.

Required behavior:

- Missing required files must fail loudly with a clear missing required files error.
- Silent empty reports when required evidence is missing are not acceptable.
- Preserve run ID, barcode, sample ID, file kind, and raw source values.
- Do not equate FlowQ/SNVQ with Illumina Q-score.
- Emit `_mqc.tsv` outputs that MultiQC and QEO can parse without crawling arbitrary run directories.
- Keep Ultima run QC outside routine final MultiQC unless a parser-backed run-QC target explicitly enables it.

The generated evidence remains DayOA output. Dewey registration and QEO observation happen after artifact generation.

