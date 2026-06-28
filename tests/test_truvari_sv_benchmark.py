from __future__ import annotations

import csv
import importlib.util
import json
import re
import sys
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def test_truvari_sv_rule_surface_is_shell_only_and_explicit_truth_config() -> None:
    text = _read("workflow/rules/truvari_sv_benchmark.smk")
    schema = _read("workflow/schemas/config.schema.yaml")
    snakefile = _read("workflow/Snakefile")
    multiqc = _read("config/external_tools/multiqc_config.yaml")

    assert not re.search(r"^\s*(run|script):", text, flags=re.MULTILINE)
    for rule_name in (
        "rule truvari_sv_benchmark_roi:",
        "rule parse_truvari_sv_summary_roi:",
        "rule prep_for_truvari_sv_concordance:",
        "rule produce_sv_concordances:",
    ):
        assert rule_name in text

    assert "truvari bench" in text
    assert "-b {input.truth_vcf:q}" in text
    assert "-c {input.query_vcf:q}" in text
    assert "--includebed {input.truth_bed:q}" in text
    assert 'rm -rf "$outdir"' in text
    assert 'tmpdir="$(dirname "$outdir")/.truvari_tmp_$(basename "$outdir")"' in text
    assert 'mkdir -p "$(dirname "$outdir")" "$(dirname {log:q})"' in text
    assert 'export TMPDIR="$tmpdir"' in text
    assert 'mkdir -p "$outdir"' not in text
    assert "workflow/scripts/parse_truvari_summary.py one" in text
    assert "workflow/scripts/parse_truvari_summary.py aggregate" in text
    assert 'config.get("truvari_sv_benchmark")' in text
    assert '"truthsets"' in text
    assert "def _truvari_sv_samples" in text
    assert "set(SAMPS)" in text
    assert "selected no jobs" in text
    assert "truth_vcf" in text
    assert "truth_tbi" in text
    assert "truth_bed" in text
    assert "CONCORDANCE_CONTROL_PATH" not in text
    assert "get_samp_concordance_truth_dir" not in text
    assert "get_truth_vcf" not in text
    assert "truvari_sv_benchmark:" in schema
    assert "truthsets:" in schema
    assert "truth_vcf:" in schema
    assert "truth_tbi:" in schema
    assert "truth_bed:" in schema
    assert 'include: "rules/truvari_sv_benchmark.smk"' in snakefile
    assert "giab_sv_concordance" in multiqc
    assert "other_reports/giab_sv_concordance_mqc.tsv" in multiqc


def test_truvari_parser_writes_stage_specific_mqc_tsv(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/parse_truvari_summary.py",
        "parse_truvari_summary_under_test",
    )
    summary = tmp_path / "summary.json"
    summary.write_text(
        json.dumps(
            {
                "TP-base": 17,
                "TP-comp": 16,
                "FP": 3,
                "FN": 4,
                "precision": 0.8421052632,
                "recall": 0.8095238095,
                "f1": 0.825492,
                "base cnt": 21,
                "comp cnt": 19,
                "TP-comp_TP-gt": 15,
                "TP-comp_FP-gt": 1,
                "TP-base_TP-gt": 15,
                "TP-base_FP-gt": 2,
                "gt_concordance": 0.9375,
            }
        ),
        encoding="utf-8",
    )
    output = tmp_path / "mqc.tsv"

    module.main(
        [
            "one",
            "--summary",
            str(summary),
            "--output",
            str(output),
            "--sample",
            "HG002",
            "--stage-sample",
            "HG002.sent.dmd.tiddit",
            "--roi",
            "giab_sv_v0_6",
            "--alt-id",
            "HG002",
            "--aligner",
            "sent",
            "--deduper",
            "dmd",
            "--sv-caller",
            "tiddit",
            "--truth-vcf",
            "/truth/HG002.sv.vcf.gz",
            "--query-vcf",
            "/query/HG002.tiddit.sv.sort.vcf.gz",
        ]
    )

    rows = _read_tsv(output)
    assert rows == [
        {
            "Sample": "HG002.sent.dmd.tiddit.giab_sv_v0_6",
            "InputSample": "HG002",
            "base_sample": "HG002",
            "Aligner": "sent",
            "Deduper": "dmd",
            "SVCaller": "tiddit",
            "AltId": "HG002",
            "ROI": "giab_sv_v0_6",
            "TP-base": "17",
            "TP-comp": "16",
            "FP": "3",
            "FN": "4",
            "Precision": "0.8421052632",
            "Sensitivity-Recall": "0.8095238095",
            "Fscore": "0.825492",
            "BaseCount": "21",
            "CompCount": "19",
            "BaseSizeFiltered": "",
            "CompSizeFiltered": "",
            "BaseGtFiltered": "",
            "CompGtFiltered": "",
            "TP-comp_TP-gt": "15",
            "TP-comp_FP-gt": "1",
            "TP-base_TP-gt": "15",
            "TP-base_FP-gt": "2",
            "GtPrecision": "",
            "GtRecall": "",
            "GtFscore": "",
            "GtConcordance": "0.9375",
            "TruthVCF": "/truth/HG002.sv.vcf.gz",
            "QueryVCF": "/query/HG002.tiddit.sv.sort.vcf.gz",
        }
    ]


def test_truvari_parser_accepts_legacy_tp_call_keys() -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/parse_truvari_summary.py",
        "parse_truvari_summary_legacy_under_test",
    )

    row = module.summary_to_row(
        {
            "TP-base": 7,
            "TP-call": 6,
            "call cnt": 8,
            "TP-call_TP-gt": 5,
            "TP-call_FP-gt": 1,
        },
        sample="HG003",
        stage_sample="HG003.ont.na.manta",
        roi="giab_sv",
        alt_id="HG003",
        aligner="ont",
        deduper="na",
        sv_caller="manta",
        truth_vcf="/truth/HG003.vcf.gz",
        query_vcf="/query/HG003.vcf.gz",
    )

    assert row["Sample"] == "HG003.ont.na.manta.giab_sv"
    assert row["TP-base"] == "7"
    assert row["TP-comp"] == "6"
    assert row["CompCount"] == "8"
    assert row["TP-comp_TP-gt"] == "5"
    assert row["TP-comp_FP-gt"] == "1"


def test_truvari_parser_aggregate_writes_header_for_empty_inputs(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/parse_truvari_summary.py",
        "parse_truvari_summary_aggregate_under_test",
    )
    output = tmp_path / "aggregate.tsv"

    module.main(["aggregate", "--output", str(output)])

    lines = output.read_text(encoding="utf-8").splitlines()
    assert lines == ["\t".join(module.FIELDNAMES)]
