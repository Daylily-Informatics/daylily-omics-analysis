from __future__ import annotations

import json
import py_compile
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def test_run_qc_rules_are_shell_only_and_separate_from_final_multiqc() -> None:
    rules = _read("workflow/rules/run_qc_reports.smk")
    final_multiqc = _read("workflow/rules/multiqc_final_wgs.smk")
    snakefile = _read("workflow/Snakefile")

    assert re.search(r"^\s*run:", rules, flags=re.MULTILINE) is None
    assert re.search(r"^\s*script:", rules, flags=re.MULTILINE) is None
    assert 'include: "rules/run_qc_reports.smk"' in snakefile
    assert "rule illumina_run_qc_fetch_metric_subset:" in rules
    assert "rule illumina_run_qc_interop_summary:" in rules
    assert "rule illumina_run_qc_checkqc_json:" in rules
    assert "rule illumina_run_qc_multiqc:" in rules
    assert "rule produce_run_qc_reports:" in rules
    assert "run_qc/" in rules
    assert "run_qc/" not in final_multiqc
    assert "produce_run_qc_reports" not in final_multiqc


def test_illumina_run_qc_contract_uses_explicit_inputs_and_metric_subset() -> None:
    rules = _read("workflow/rules/run_qc_reports.smk")

    for required in (
        "run_qc.illumina.run_s3_uri is required",
        "run_qc.illumina.profile is required",
        "run_qc.illumina.profile must not be default",
        "run_qc.illumina.region is required",
    ):
        assert required in rules

    assert "AWS_PROFILE={params.profile:q} AWS_REGION={params.region:q}" in rules
    assert "aws s3 cp \"$run_uri/$rel\"" in rules
    assert "aws s3 sync" not in rules
    assert "--recursive" not in rules
    assert "*.fastq.gz" not in rules
    assert "Analysis/1/Data/BCLConvert/fastq/Reports/Quality_Metrics.csv" in rules
    assert "InterOp/QMetricsOut.bin" in rules
    assert "InterOp/SummaryRunMetricsOut.bin" in rules


def test_checkqc_interop_and_placeholder_contracts_fail_loudly() -> None:
    rules = _read("workflow/rules/run_qc_reports.smk")
    summarizer = _read("workflow/scripts/summarize_run_qc_report.py")

    assert "interop_summary {params.source_run:q} --csv=1" in rules
    assert "interop_index-summary {params.source_run:q} --csv=1" in rules
    assert "checkqc --json {params.source_run:q}" in rules
    assert "-m checkqc" in rules
    assert "-m interop" in rules
    assert "run_qc.ont.metrics_path" in summarizer
    assert "run_qc.ultima.metrics_path" in summarizer
    assert "does not exist" in summarizer
    assert "is empty" in summarizer


def test_read_fate_river_is_generalized_and_explicit() -> None:
    river = _read("bin/build_illumina_read_fate_river.py")
    rules = _read("workflow/rules/run_qc_reports.smk")

    assert "DEFAULT_RUN_S3_URI" not in river
    assert "DEFAULT_LOCAL_INTEROP_DIR" not in river
    assert "20260507_LH01106_0005_A23K3JVLT4" not in river
    assert "23AME" not in river
    assert 'parser.add_argument("--run-s3-uri", required=True)' in river
    assert "--report-prefix" in river
    assert "--report-title" in river
    assert "pip" not in river[river.index("def install_interop_if_needed") :]
    assert "rule illumina_run_qc_read_fate_river:" in rules
    assert "rule produce_read_fate_river:" in rules
    assert "bin/build_illumina_read_fate_river.py" in rules


def test_run_qc_scripts_compile() -> None:
    for path in (
        "workflow/scripts/summarize_run_qc_report.py",
        "bin/build_illumina_read_fate_river.py",
    ):
        py_compile.compile(str(REPO_ROOT / path), doraise=True)


def test_summarize_run_qc_report_outputs_and_missing_input_failure(tmp_path: Path) -> None:
    interop = tmp_path / "interop_summary.csv"
    interop.write_text("Lane,Reads\n1,10\n", encoding="utf-8")
    index = tmp_path / "interop_index_summary.csv"
    index.write_text("Lane,Index,Reads\n1,ACGT,5\n", encoding="utf-8")
    checkqc = tmp_path / "checkqc.json"
    checkqc.write_text(
        json.dumps({"instrument_and_reagent_type": "NovaSeq", "warnings": []}),
        encoding="utf-8",
    )
    html = tmp_path / "ilmn.html"
    tsv = tmp_path / "ilmn.tsv"
    done = tmp_path / "ilmn.done"

    result = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow/scripts/summarize_run_qc_report.py"),
            "--platform",
            "ILMN",
            "--run-s3-uri",
            "s3://bucket/run",
            "--interop-summary",
            str(interop),
            "--interop-index-summary",
            str(index),
            "--checkqc-json",
            str(checkqc),
            "--output-html",
            str(html),
            "--output-tsv",
            str(tsv),
            "--done",
            str(done),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "Illumina Run QC Report" in html.read_text(encoding="utf-8")
    assert "run_s3_uri\ts3://bucket/run" in tsv.read_text(encoding="utf-8")
    assert done.read_text(encoding="utf-8") == "done\n"

    missing = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow/scripts/summarize_run_qc_report.py"),
            "--platform",
            "ONT",
            "--metrics-path",
            str(tmp_path / "missing.tsv"),
            "--output-html",
            str(tmp_path / "ont.html"),
            "--output-tsv",
            str(tmp_path / "ont.tsv"),
            "--done",
            str(tmp_path / "ont.done"),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert missing.returncode != 0
    assert "does not exist" in missing.stderr
