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


def _load_ganon2_summary_module():
    script_path = REPO_ROOT / "workflow/scripts/summarize_unmapped_ganon2.py"
    spec = importlib.util.spec_from_file_location(
        "summarize_unmapped_ganon2_under_test", script_path
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_sourmash_summary_module():
    script_path = REPO_ROOT / "workflow/scripts/summarize_unmapped_sourmash.py"
    spec = importlib.util.spec_from_file_location(
        "summarize_unmapped_sourmash_under_test", script_path
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
    assert "rule unmapped_metagenomics_ganon2_quick:" in rules
    assert "rule unmapped_metagenomics_ganon2_summary:" in rules
    assert "rule unmapped_metagenomics_ganon2_multiqc:" in rules
    assert "rule produce_unmapped_metagenomics_ganon2_quick:" in rules
    assert "rule unmapped_metagenomics_sourmash_gather:" in rules
    assert "rule unmapped_metagenomics_sourmash_summary:" in rules
    assert "rule unmapped_metagenomics_sourmash_multiqc:" in rules
    assert "rule produce_unmapped_metagenomics_sourmash_gather:" in rules
    assert "rule produce_metagenomics:" in rules
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


def test_unmapped_metagenomics_extracts_pass_qc_unmapped_reads_for_ganon2() -> None:
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    for expected in (
        "rule unmapped_metagenomics_ganon2_quick:",
        "samtools quickcheck -v {input.alignment:q}",
        "samtools view",
        "-f 4",
        "-F 0xB00",
        "samtools fastq",
        "ganon classify",
        "--db-prefix {params.ganon2_db_prefixes:q}",
        "--output-prefix {params.output_prefix:q}",
        "--single-reads {output.fastq:q}",
        "--threads {threads}",
        "workflow/scripts/summarize_unmapped_ganon2.py",
        "--read-limit {params.read_limit:q}",
        "for prefix in {params.ganon2_db_prefixes:q}; do",
        "test -s \"$prefix\".tax",
        ".hibf",
        ".ibf",
    ):
        assert expected in rules

    assert "human_unmapped.ganon2.quick.fastq.gz" in rules
    assert ".ganon2.quick.tre" in rules
    assert ".ganon2.quick.rep" in rules
    assert "--max-reads" not in rules


def test_unmapped_metagenomics_extracts_pass_qc_unmapped_reads_for_sourmash() -> None:
    rules = _read("workflow/rules/unmapped_metagenomics.smk")

    for expected in (
        "rule unmapped_metagenomics_sourmash_gather:",
        "samtools quickcheck -v {input.alignment:q}",
        "samtools view",
        "-f 4",
        "-F 0xB00",
        "samtools fastq",
        "sourmash sketch dna",
        "--name {params.sample_id:q}",
        "-p k={params.sourmash_ksize},scaled={params.sourmash_scaled},abund",
        "sourmash gather",
        "--threshold-bp {params.sourmash_threshold_bp}",
        "{params.sourmash_databases:q}",
        "workflow/scripts/summarize_unmapped_sourmash.py",
        "--sourmash-signature {output.sig:q}",
        "--sourmash-gather-csv {output.gather_csv:q}",
        "--read-limit {params.read_limit:q}",
        "for database in {params.sourmash_databases:q}; do",
    ):
        assert expected in rules

    assert "human_unmapped.sourmash.fastq.gz" in rules
    assert ".sourmash.sig" in rules
    assert ".sourmash.gather.csv" in rules
    assert "--max-reads" not in rules


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
        "produce_unmapped_metagenomics_ganon2_quick requires an",
        "unmapped_metagenomics.ganon2_db_prefixes",
        "unmapped_metagenomics.read_limit must be explicitly set to 'all'",
        "produce_unmapped_metagenomics_sourmash_gather requires an",
        "unmapped_metagenomics.sourmash_databases",
        "unmapped_metagenomics.sourmash_ksize",
        "unmapped_metagenomics.sourmash_scaled",
        "unmapped_metagenomics.sourmash_moltype",
        "unmapped_metagenomics.sourmash_threshold_bp",
        "capped unmapped-read sourmash gather fingerprinting is not supported",
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
        "reports/unmapped_metagenomics_ganon2.multiqc.html",
        "reports/unmapped_metagenomics_sourmash.multiqc.html",
        "unmapped_metagenomics_multiqc_config.yaml",
        "unmapped_metagenomics_ganon2_multiqc_config.yaml",
        "unmapped_metagenomics_sourmash_multiqc_config.yaml",
        "-m kraken",
        "-m custom_content",
        "custom_data:",
        "Unmapped-read Metagenomics",
        "Unmapped-read Ganon2 Metagenomics",
        "Unmapped-read Sourmash Gather Fingerprint",
        "fn: \"other_reports/unmapped_metagenomics_mqc.tsv\"",
        "fn: \"other_reports/unmapped_metagenomics_ganon2_mqc.tsv\"",
        "fn: \"other_reports/unmapped_metagenomics_sourmash_mqc.tsv\"",
        "reports/unmapped_metagenomics_sourmash.multiqc.html",
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
    assert '"unmapped_metagenomics_ganon2"' in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert '"metagenomics"' in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert '"unmapped_metagenomics_sourmash"' in common[
        common.index("MULTIQC_QC_LONG_RUNNING_TOOLS") : common.index("SUPPORTED_HTD_CALLERS")
    ]
    assert (
        'qc_tool_enabled(\n'
        '        "unmapped_metagenomics", long_running=True, default=False\n'
        "    )"
    ) in final
    assert "_validate_unmapped_metagenomics_multiqc_config()" in final
    assert "_validate_unmapped_metagenomics_ganon2_multiqc_config()" in final
    assert "_validate_unmapped_metagenomics_sourmash_multiqc_config()" in final
    assert "_metagenomics_enabled_for_multiqc()" in final
    assert "other_reports/unmapped_metagenomics_mqc.tsv" in final
    assert "other_reports/unmapped_metagenomics_ganon2_mqc.tsv" in final
    assert "other_reports/unmapped_metagenomics_sourmash_mqc.tsv" in final
    assert ".kraken2.quick.report.txt" in final
    assert "enable_tools=['metagenomics']" in final
    assert "enable_tools=['unmapped_metagenomics_ganon2']" in final
    assert "enable_tools=['unmapped_metagenomics_sourmash']" in final
    assert "unmapped_metagenomics.ganon2_db_prefixes" in final
    assert "unmapped_metagenomics.sourmash_databases" in final
    assert "dedupers = qc_contamination_dedupers()" in final
    assert "enable_tools=['unmapped_metagenomics']" in final

    assert "def stage_kraken2_report" in staging
    assert "def stage_ganon2_sources_from_custom_row" in staging
    assert "def stage_sourmash_sources_from_custom_row" in staging
    assert "native/kraken" in staging
    assert "native/ganon2" in staging
    assert "native/sourmash" in staging
    assert "kraken2_report" in staging
    assert "ganon2_tree_report" in staging
    assert "sourmash_signature" in staging
    assert "sourmash_gather_csv" in staging

    assert "\n  - kraken\n" in config
    assert "\n  - unmapped_metagenomics\n" in config
    assert "\n  - unmapped_metagenomics_ganon2\n" in config
    assert "\n  - unmapped_metagenomics_sourmash\n" in config
    assert "unmapped_metagenomics:" in config
    assert "unmapped_metagenomics_ganon2:" in config
    assert "unmapped_metagenomics_sourmash:" in config
    assert "other_reports/unmapped_metagenomics_mqc.tsv" in config
    assert "other_reports/unmapped_metagenomics_ganon2_mqc.tsv" in config
    assert "other_reports/unmapped_metagenomics_sourmash_mqc.tsv" in config


def test_unmapped_metagenomics_envs_have_classifier_and_samtools() -> None:
    env = yaml.safe_load(_read("workflow/envs/unmapped_metagenomics_v0.1.yaml"))
    ganon_env = yaml.safe_load(
        _read("workflow/envs/unmapped_metagenomics_ganon2_v0.1.yaml")
    )
    sourmash_env = yaml.safe_load(
        _read("workflow/envs/unmapped_metagenomics_sourmash_v0.1.yaml")
    )

    deps = {str(dep).split("=")[0] for dep in env["dependencies"]}
    ganon_deps = {str(dep).split("=")[0] for dep in ganon_env["dependencies"]}
    sourmash_deps = {str(dep).split("=")[0] for dep in sourmash_env["dependencies"]}
    assert {"kraken2", "samtools", "python"} <= deps
    assert {"ganon", "samtools", "python"} <= ganon_deps
    assert {"sourmash", "samtools", "python"} <= sourmash_deps


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


def test_summarize_unmapped_ganon2_rejects_capped_read_limit() -> None:
    module = _load_ganon2_summary_module()

    assert "read_limit" in module.FIELDNAMES
    with pytest.raises(ValueError, match="--read-limit must be 'all'"):
        module._build_row(
            SimpleNamespace(database="/refs/ganon/bac;/refs/ganon/vir", read_limit="100000")
        )


def test_summarize_unmapped_ganon2_writes_mqc_style_tsv(tmp_path: Path) -> None:
    module = _load_ganon2_summary_module()
    fastq = tmp_path / "unmapped.fastq.gz"
    tre = tmp_path / "sample.ganon2.quick.tre"
    rep = tmp_path / "sample.ganon2.quick.rep"
    output = tmp_path / "sample.unmapped_metagenomics_ganon2_mqc.tsv"

    with gzip.open(fastq, "wt", encoding="utf-8") as handle:
        for idx in range(1, 5):
            handle.write(f"@read{idx}\nACGT\n+\nFFFF\n")

    tre.write_text(
        "\n".join(
            [
                "unclassified\tunclassified\t\tunclassified\t0\t0\t0\t1\t25.00000",
                "root\t1\t1\troot\t0\t0\t3\t3\t75.00000",
                "species\t562\t1|2|562\tEscherichia coli\t2\t0\t0\t2\t50.00000",
                "species\t1280\t1|2|1280\tStaphylococcus aureus\t1\t0\t0\t1\t25.00000",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    rep.write_text(
        "\n".join(
            [
                "H1\t562\t2\t2\t0\tspecies\tEscherichia coli",
                "H1\t1280\t1\t1\t0\tspecies\tStaphylococcus aureus",
                "#total_classified\t3",
                "#total_unclassified\t1",
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
                "/refs/ganon/bac;/refs/ganon/vir",
                "--read-limit",
                "all",
                "--unmapped-fastq",
                str(fastq),
                "--ganon2-report",
                str(tre),
                "--ganon2-rep",
                str(rep),
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
            "classifier": "ganon2",
            "database": "/refs/ganon/bac;/refs/ganon/vir",
            "read_limit": "all",
            "input_fastq": str(fastq),
            "input_fastq_reads": "4",
            "ganon2_report": str(tre),
            "ganon2_rep": str(rep),
            "reads_processed": "4",
            "reads_classified": "3",
            "classified_pct": "75.0000",
            "reads_unclassified": "1",
            "unclassified_pct": "25.0000",
            "top_target": "562",
            "top_rank": "species",
            "top_taxon": "Escherichia coli",
            "top_taxon_reads": "2",
            "top_taxon_pct": "50.0000",
        }
    ]


def test_summarize_unmapped_sourmash_rejects_capped_read_limit() -> None:
    module = _load_sourmash_summary_module()

    assert "read_limit" in module.FIELDNAMES
    assert "sourmash_signature" in module.FIELDNAMES
    assert "sourmash_gather_csv" in module.FIELDNAMES
    with pytest.raises(ValueError, match="--read-limit must be 'all'"):
        module._build_row(
            SimpleNamespace(
                database="/refs/sourmash/dayoa.zip",
                read_limit="100000",
                sourmash_ksize="31",
                sourmash_scaled="1000",
                sourmash_moltype="DNA",
                sourmash_threshold_bp="3000",
            )
        )


def test_summarize_unmapped_sourmash_writes_mqc_style_tsv(tmp_path: Path) -> None:
    module = _load_sourmash_summary_module()
    fastq = tmp_path / "unmapped.fastq.gz"
    sig = tmp_path / "sample.sourmash.sig"
    gather_csv = tmp_path / "sample.sourmash.gather.csv"
    output = tmp_path / "sample.unmapped_metagenomics_sourmash_mqc.tsv"

    with gzip.open(fastq, "wt", encoding="utf-8") as handle:
        for idx in range(1, 5):
            handle.write(f"@read{idx}\nACGT\n+\nFFFF\n")

    sig.write_text("{\"class\":\"sourmash_signature\"}\n", encoding="utf-8")
    gather_csv.write_text(
        ",".join(
            [
                "unique_intersect_bp",
                "intersect_bp",
                "f_unique_to_query",
                "f_unique_weighted",
                "filename",
                "name",
                "md5",
                "gather_result_rank",
                "query_bp",
                "ksize",
                "moltype",
                "scaled",
                "query_n_hashes",
            ]
        )
        + "\n"
        + ",".join(
            [
                "2000",
                "3000",
                "0.200000",
                "0.250000",
                "/refs/sourmash/ecoli.sig",
                "Escherichia coli",
                "aaaaaaaa",
                "0",
                "10000",
                "31",
                "DNA",
                "1000",
                "10",
            ]
        )
        + "\n"
        + ",".join(
            [
                "1000",
                "1200",
                "0.100000",
                "0.125000",
                "/refs/sourmash/saureus.sig",
                "Staphylococcus aureus",
                "bbbbbbbb",
                "1",
                "10000",
                "31",
                "DNA",
                "1000",
                "10",
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
                "/refs/sourmash/dayoa_qc.zip",
                "--read-limit",
                "all",
                "--unmapped-fastq",
                str(fastq),
                "--sourmash-signature",
                str(sig),
                "--sourmash-gather-csv",
                str(gather_csv),
                "--sourmash-ksize",
                "31",
                "--sourmash-scaled",
                "1000",
                "--sourmash-moltype",
                "DNA",
                "--sourmash-threshold-bp",
                "3000",
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
            "classifier": "sourmash_gather",
            "database": "/refs/sourmash/dayoa_qc.zip",
            "read_limit": "all",
            "input_fastq": str(fastq),
            "input_fastq_reads": "4",
            "sourmash_signature": str(sig),
            "sourmash_gather_csv": str(gather_csv),
            "sourmash_ksize": "31",
            "sourmash_scaled": "1000",
            "sourmash_moltype": "DNA",
            "sourmash_threshold_bp": "3000",
            "gather_matches": "2",
            "query_bp": "10000",
            "query_n_hashes": "10",
            "weighted_found_fraction": "0.375000",
            "unique_intersect_bp": "3000",
            "top_name": "Escherichia coli",
            "top_md5": "aaaaaaaa",
            "top_filename": "/refs/sourmash/ecoli.sig",
            "top_rank": "0",
            "top_f_unique_weighted": "0.250000",
            "top_f_unique_to_query": "0.200000",
            "top_intersect_bp": "3000",
            "top_unique_intersect_bp": "2000",
        }
    ]
