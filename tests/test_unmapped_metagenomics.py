from __future__ import annotations

import csv
import gzip
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _load_summary_module():
    script_path = REPO_ROOT / "workflow/scripts/summarize_unmapped_metagenomics.py"
    spec = importlib.util.spec_from_file_location(
        "summarize_unmapped_metagenomics_under_test", script_path
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_unmapped_metagenomics_rules_are_shell_only_and_included() -> None:
    snakefile = _read("workflow/Snakefile")
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    assert 'include: "rules/unmapped_metagenomics.smk"' in snakefile
    assert "rule unmapped_metagenomics_kraken2_quick:" in rules
    assert "rule unmapped_metagenomics_summary:" in rules
    assert "rule unmapped_metagenomics_multiqc:" in rules
    assert "rule produce_unmapped_metagenomics_quick:" in rules
    assert "\n    run:" not in rules
    assert "\n    script:" not in rules


def test_unmapped_metagenomics_extracts_pass_qc_unmapped_reads_for_kraken2() -> None:
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    for expected in (
        "samtools quickcheck -v {input.alignment:q}",
        "samtools view",
        "-f 4",
        "-F 0xB00",
        "samtools fastq",
        "kraken2",
        "--quick",
        "--db {params.kraken2_db:q}",
        "--threads {threads}",
        "--gzip-compressed",
        "--report {output.report:q}",
        "{params.memory_mapping_flag}",
        "workflow/scripts/summarize_unmapped_metagenomics.py",
        "--read-limit {params.read_limit:q}",
    ):
        assert expected in rules

    assert "awk -v max_reads" not in rules
    assert "--max-reads" not in rules
    assert "max_reads" not in rules
    assert "test -d {params.kraken2_db:q}" in rules
    assert "unmapped_metagenomics.read_limit must be 'all'" in rules


def test_unmapped_metagenomics_requires_explicit_config_and_high_threads() -> None:
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    for expected in (
        "unmapped_metagenomics config block",
        "unmapped_metagenomics.kraken2_db",
        "unmapped_metagenomics.threads",
        "unmapped_metagenomics.mem_mb",
        "unmapped_metagenomics.partition",
        "unmapped_metagenomics.read_limit='all'",
        'minimum=16',
    ):
        assert expected in rules


def test_unmapped_metagenomics_memory_mapping_requires_explicit_true() -> None:
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    for expected in (
        "value = cfg.get(key, default)",
        'if normalized == "true":',
        'if normalized == "false":',
        'return "--memory-mapping"',
        "_unmapped_metagenomics_bool(\"memory_mapping\", default=False)",
        "must be true or false; saw",
    ):
        assert expected in rules


def test_unmapped_metagenomics_summary_and_focused_multiqc_wiring() -> None:
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    for expected in (
        "other_reports/unmapped_metagenomics_mqc.tsv",
        "reports/unmapped_metagenomics.multiqc.html",
        "unmapped_metagenomics_multiqc_config.yaml",
        "-m kraken",
        "-m custom_content",
        "custom_data:",
        "Unmapped-read Metagenomics",
        "fn: \"other_reports/unmapped_metagenomics_mqc.tsv\"",
    ):
        assert expected in rules


def test_unmapped_metagenomics_final_multiqc_is_explicitly_gated() -> None:
    common = _read("workflow/rules/common.smk")
    final = _read("workflow/rules/multiqc_final_wgs.smk")
    staging = _read("workflow/scripts/stage_multiqc_inputs.py")
    config = _read("config/external_tools/multiqc_config.yaml")

    assert '"unmapped_metagenomics"' in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert (
        'qc_tool_enabled(\n'
        '        "unmapped_metagenomics", long_running=True, default=False\n'
        "    )"
    ) in final
    assert "_validate_unmapped_metagenomics_multiqc_config()" in final
    assert "other_reports/unmapped_metagenomics_mqc.tsv" in final
    assert ".kraken2.quick.report.txt" in final
    assert "dedupers = qc_contamination_dedupers()" in final
    assert "enable_tools=['unmapped_metagenomics']" in final

    assert "def stage_kraken2_report" in staging
    assert "native/kraken" in staging
    assert "kraken2_report" in staging

    assert "\n  - kraken\n" in config
    assert "\n  - unmapped_metagenomics\n" in config
    assert "unmapped_metagenomics:" in config
    assert "other_reports/unmapped_metagenomics_mqc.tsv" in config


def test_unmapped_metagenomics_env_has_kraken2_and_samtools() -> None:
    env = yaml.safe_load(_read("workflow/envs/unmapped_metagenomics_v0.1.yaml"))

    deps = {str(dep).split("=")[0] for dep in env["dependencies"]}
    assert {"kraken2", "samtools", "python"} <= deps


def test_summarize_unmapped_metagenomics_rejects_capped_read_limit() -> None:
    module = _load_summary_module()

    assert "read_limit" in module.FIELDNAMES
    assert "max_reads" not in module.FIELDNAMES
    with pytest.raises(ValueError, match="--read-limit must be 'all'"):
        module._build_row(
            SimpleNamespace(database="/refs/kraken2", read_limit="100000")
        )


def test_summarize_unmapped_metagenomics_writes_mqc_style_tsv(tmp_path: Path) -> None:
    module = _load_summary_module()
    fastq = tmp_path / "unmapped.fastq.gz"
    report = tmp_path / "sample.kraken2.report.txt"
    kraken_output = tmp_path / "sample.kraken2.output.tsv"
    output = tmp_path / "sample.unmapped_metagenomics_mqc.tsv"

    with gzip.open(fastq, "wt", encoding="utf-8") as handle:
        for idx in range(1, 5):
            handle.write(f"@read{idx}\nACGT\n+\nFFFF\n")

    report.write_text(
        "\n".join(
            [
                "25.00\t1\t1\tU\t0\tunclassified",
                "75.00\t3\t0\tR\t1\troot",
                "50.00\t2\t2\tS\t562\t  Escherichia coli",
                "25.00\t1\t1\tS\t1280\t  Staphylococcus aureus",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    kraken_output.write_text(
        "\n".join(
            [
                "C\tread1\t562\t100\t562:100",
                "U\tread2\t0\t100\t0:100",
                "C\tread3\t562\t100\t562:100",
                "C\tread4\t1280\t100\t1280:100",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    assert (
        module.main(
            [
                "--sample",
                "HG002.sent.dmd",
                "--base-sample",
                "HG002",
                "--aligner",
                "sent",
                "--deduper",
                "dmd",
                "--database",
                "/refs/kraken2",
                "--read-limit",
                "all",
                "--unmapped-fastq",
                str(fastq),
                "--kraken-report",
                str(report),
                "--kraken-output",
                str(kraken_output),
                "--output",
                str(output),
            ]
        )
        == 0
    )

    with output.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))

    assert rows == [
        {
            "Sample": "HG002.sent.dmd",
            "base_sample": "HG002",
            "aligner": "sent",
            "deduper": "dmd",
            "classifier": "kraken2",
            "database": "/refs/kraken2",
            "read_limit": "all",
            "input_fastq": str(fastq),
            "input_fastq_reads": "4",
            "kraken_report": str(report),
            "kraken_output": str(kraken_output),
            "reads_processed": "4",
            "reads_classified": "3",
            "classified_pct": "75.0000",
            "reads_unclassified": "1",
            "unclassified_pct": "25.0000",
            "top_taxid": "562",
            "top_rank": "S",
            "top_taxon": "Escherichia coli",
            "top_taxon_reads": "2",
            "top_taxon_pct": "50.0000",
        }
    ]
