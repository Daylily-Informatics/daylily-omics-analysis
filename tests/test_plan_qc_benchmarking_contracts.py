from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def test_new_qc_benchmarking_rules_are_shell_only() -> None:
    for path in (
        "workflow/rules/run_qc_reports.smk",
        "workflow/rules/truvari_sv_benchmark.smk",
        "workflow/rules/unmapped_metagenomics.smk",
    ):
        text = _read(path)
        assert re.search(r"^\s*run:", text, flags=re.MULTILINE) is None, path
        assert re.search(r"^\s*script:", text, flags=re.MULTILINE) is None, path
        assert re.search(r"^\s*shell:", text, flags=re.MULTILINE) is not None, path


def test_qc_benchmarking_docs_cover_new_report_surfaces() -> None:
    docs = _read("docs/ops/multiqc_qc_targets.md")
    catalog = _read("docs/catalog_of_tools.md")

    for expected in (
        "produce_illumina_run_qc",
        "produce_read_fate_river",
        "produce_ont_run_qc",
        "produce_ultima_run_qc",
        "produce_unmapped_metagenomics_quick",
        "giab_sv_concordance_mqc.tsv",
    ):
        assert expected in docs

    for expected in (
        "Illumina InterOp",
        "CheckQC",
        "Illumina read-fate RIVER",
        "Kraken2 unmapped-read screen",
        "Truvari SV benchmark",
    ):
        assert expected in catalog
