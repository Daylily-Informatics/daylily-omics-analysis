from __future__ import annotations

import csv
import importlib.util
import sys
from decimal import Decimal
from pathlib import Path
from types import ModuleType

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "workflow" / "scripts" / "build_multiqc_intro.py"
HEADER_SCRIPT_PATH = REPO_ROOT / "workflow" / "scripts" / "build_multiqc_header.py"


def _load_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("build_multiqc_intro_under_test", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"Unable to import {SCRIPT_PATH.relative_to(REPO_ROOT)}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["build_multiqc_intro_under_test"] = module
    spec.loader.exec_module(module)
    return module


def _load_header_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "build_multiqc_header_under_test", HEADER_SCRIPT_PATH
    )
    if spec is None or spec.loader is None:
        raise AssertionError(
            f"Unable to import {HEADER_SCRIPT_PATH.relative_to(REPO_ROOT)}"
        )
    module = importlib.util.module_from_spec(spec)
    sys.modules["build_multiqc_header_under_test"] = module
    spec.loader.exec_module(module)
    return module


def _write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> Path:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return path


def _write_samples(path: Path, sample_ids: list[str]) -> Path:
    return _write_tsv(
        path,
        ["SAMPLEID", "SAMPLESOURCE"],
        [{"SAMPLEID": sample_id, "SAMPLESOURCE": "blood"} for sample_id in sample_ids],
    )


def _benchmark_row(rule: str, task_cost: str) -> dict[str, str]:
    rule_prefix = rule.split(".", maxsplit=1)[0]
    return {
        "task_cost": task_cost,
        "rule": rule,
        "combined_rule": f"{rule}-HG002",
        "rule_prefix": rule_prefix,
    }


def _write_benchmark(path: Path, rows: list[dict[str, str]]) -> Path:
    return _write_tsv(
        path,
        ["task_cost", "rule", "combined_rule", "rule_prefix"],
        rows,
    )


def test_intro_yaml_reports_total_and_per_sample_costs(tmp_path: Path) -> None:
    module = _load_module()
    benchmark = _write_benchmark(
        tmp_path / "rules_benchmark_data_mqc.tsv",
        [
            _benchmark_row("sent.alNsort", "2.00"),
            _benchmark_row("sent.smd.mrkdup", "1.00"),
            _benchmark_row("sent.deep19.1", "3.00"),
            _benchmark_row("multiqc.final", "4.00"),
        ],
    )
    samples = _write_samples(tmp_path / "samples.tsv", ["HG001", "HG002"])

    config = yaml.safe_load(module.build_intro_yaml(benchmark, samples, "multiqc results"))
    intro = config["intro_text"]

    assert intro.startswith("<details>")
    for expected in (
        "Samples</td><td>2",
        "Benchmark tasks</td><td>4",
        "Total benchmark task_cost</td><td>$10.00",
        "Per-sample benchmark task_cost</td><td>$5.00",
        "Avg per-sample aligner task_cost</td><td>$1.00",
        "Avg per-sample deduper task_cost</td><td>$0.50",
        "Avg per-sample SNV caller task_cost</td><td>$1.50",
        "FastQC covers raw-read quality",
    ):
        assert expected in intro


def test_command_is_escaped_and_cli_writes_yaml(tmp_path: Path) -> None:
    module = _load_module()
    benchmark = _write_benchmark(
        tmp_path / "rules_benchmark_data_mqc.tsv",
        [_benchmark_row("sent.deep19.1", "1.25")],
    )
    samples = _write_samples(tmp_path / "samples.tsv", ["HG002"])
    output = tmp_path / "multiqc_intro.yaml"

    exit_code = module.main(
        [
            "--benchmark-tsv",
            str(benchmark),
            "--samples-tsv",
            str(samples),
            "--multiqc-command",
            'multiqc --title "<Day & Night>" results/$DAY',
            "--output",
            str(output),
        ]
    )

    assert exit_code == 0
    intro = yaml.safe_load(output.read_text(encoding="utf-8"))["intro_text"]
    assert "<details>" in intro
    assert (
        "<code>multiqc --title &quot;&lt;Day &amp; Night&gt;&quot; "
        "results/$DAY</code>"
    ) in intro
    assert '"<Day & Night>"' not in intro


def test_header_yaml_escapes_report_header_cost_strings(tmp_path: Path) -> None:
    module = _load_header_module()
    benchmark = _write_benchmark(
        tmp_path / "rules_benchmark_data_mqc.tsv",
        [_benchmark_row("sent.alNsort", "1.25")],
    )
    samples = _write_samples(tmp_path / "samples.tsv", ["HG002"])

    yaml_text = module.build_header_yaml(
        benchmark_tsv=benchmark,
        samples_tsv=samples,
        multiqc_command="multiqc results/$DAY",
        project_budget="fk-260509-use",
        budget_runtime="$0.0 of $300.0 spent ( 0% )",
        spot_instances="c7i.metal-48xl",
        spot_costs="median: $2.69 mean: $2.72",
        aligner_costs=r"sent.alNsort: \$1.08",
        mrkdup_cost="0 min, costing $0.00",
        results_size="1.2T",
    )

    parsed = yaml.safe_load(yaml_text)
    assert parsed["report_header_info"][4] == {
        "FQ->BAM.sort avg Costs": r"sent.alNsort: \$1.08"
    }
    assert parsed["report_header_info"][5] == {"BAM mrkdup avg Cost": "0 min, costing $0.00"}
    assert parsed["intro_text"].startswith("<details>")
    assert "multiqc results/$DAY" in parsed["intro_text"]


def test_base_multiqc_config_does_not_override_generated_intro() -> None:
    config = yaml.safe_load(
        (REPO_ROOT / "config" / "external_tools" / "multiqc_config.yaml").read_text(
            encoding="utf-8"
        )
    )

    assert "intro_text" not in config


def test_missing_required_benchmark_columns_hard_fail(tmp_path: Path) -> None:
    module = _load_module()
    benchmark = _write_tsv(
        tmp_path / "rules_benchmark_data_mqc.tsv",
        ["task_cost", "rule", "combined_rule"],
        [{"task_cost": "1.00", "rule": "sent.alNsort", "combined_rule": "sent.alNsort-HG002"}],
    )
    samples = _write_samples(tmp_path / "samples.tsv", ["HG002"])

    with pytest.raises(ValueError, match="missing required columns: rule_prefix"):
        module.summarize_costs(benchmark, samples)


def test_zero_samples_hard_fail(tmp_path: Path) -> None:
    module = _load_module()
    benchmark = _write_benchmark(
        tmp_path / "rules_benchmark_data_mqc.tsv",
        [_benchmark_row("sent.alNsort", "1.00")],
    )
    samples = _write_samples(tmp_path / "samples.tsv", [])

    with pytest.raises(ValueError, match="contains zero samples"):
        module.summarize_costs(benchmark, samples)


def test_category_buckets_are_explicit_and_deterministic(tmp_path: Path) -> None:
    module = _load_module()
    benchmark = _write_benchmark(
        tmp_path / "rules_benchmark_data_mqc.tsv",
        [
            _benchmark_row("sent.alNsort", "2.00"),
            _benchmark_row("sent.smd.mrkdup", "3.00"),
            _benchmark_row("sent.deep19.1-24", "4.00"),
            _benchmark_row("ont.clair3.merge", "5.00"),
            _benchmark_row("sent.dmd.sentd.chr16.vep", "7.00"),
            _benchmark_row("multiqc.final", "6.00"),
        ],
    )
    samples = _write_samples(tmp_path / "samples.tsv", ["HG001", "HG002"])

    summary = module.summarize_costs(benchmark, samples)

    assert module.classify_rule(_benchmark_row("sent.alNsort", "0")) == module.CATEGORY_ALIGNER
    assert module.classify_rule(_benchmark_row("sent.smd.mrkdup", "0")) == module.CATEGORY_DEDUPER
    assert module.classify_rule(_benchmark_row("ont.clair3.merge", "0")) == module.CATEGORY_SNV_CALLER
    assert module.classify_rule(_benchmark_row("sent.dmd.sentd.1-24", "0")) == module.CATEGORY_SNV_CALLER
    assert module.classify_rule(_benchmark_row("sent.dmd.sentd.chr16.vep", "0")) == module.CATEGORY_OTHER
    assert module.classify_rule(_benchmark_row("multiqc.final", "0")) == module.CATEGORY_OTHER
    assert summary.category_task_costs[module.CATEGORY_ALIGNER] == Decimal("2.00")
    assert summary.category_task_costs[module.CATEGORY_DEDUPER] == Decimal("3.00")
    assert summary.category_task_costs[module.CATEGORY_SNV_CALLER] == Decimal("9.00")
    assert summary.category_task_costs[module.CATEGORY_OTHER] == Decimal("13.00")
    assert summary.category_per_sample_costs[module.CATEGORY_SNV_CALLER] == Decimal("4.50")
