import gzip
import importlib.util
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = REPO_ROOT / "workflow" / "scripts" / "fastq_path_lists.py"
FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "comma_fastq_lists"


def _load_helper_module():
    spec = importlib.util.spec_from_file_location("fastq_path_lists", HELPER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_three_r1_three_r2_fastqs_parse_as_csv_path_lists() -> None:
    helper = _load_helper_module()
    r1_paths = [
        str(FIXTURE_DIR / f"lane{index}.BC01.R1.fastq.gz")
        for index in range(1, 4)
    ]
    r2_paths = [
        str(FIXTURE_DIR / f"lane{index}.BC01.R2.fastq.gz")
        for index in range(1, 4)
    ]

    for path in r1_paths + r2_paths:
        with gzip.open(path, "rt", encoding="utf-8") as handle:
            assert handle.readline().startswith("@lane")

    r1_value = ",".join(r1_paths)
    r2_value = ",".join(r2_paths)

    assert helper.split_fastq_path_list(r1_value) == r1_paths
    assert helper.split_fastq_path_list(r2_value) == r2_paths
    assert helper.paired_fastq_path_lists(r1_value, r2_value) == (
        r1_paths,
        r2_paths,
    )


def test_paired_fastq_path_lists_reject_mismatched_counts() -> None:
    helper = _load_helper_module()

    with pytest.raises(ValueError, match="same number of entries"):
        helper.paired_fastq_path_lists(
            "/tmp/lane1.R1.fastq.gz,/tmp/lane2.R1.fastq.gz",
            "/tmp/lane1.R2.fastq.gz",
            context="analysis unit TEST",
        )


def test_workflow_uses_direct_fastq_lists_for_multi_path_alignment_inputs() -> None:
    common = (REPO_ROOT / "workflow" / "rules" / "common.smk").read_text()
    fastqc = (REPO_ROOT / "workflow" / "rules" / "fastqc.smk").read_text()

    assert "def _row_uses_direct_fastq_list" in common
    assert "return _alignment_fastq_inputs(wildcards, \"R1\")" in common
    assert "return _alignment_fastq_inputs(wildcards, \"R2\")" in common
    assert "paths.extend(r1s if mate == \"R1\" else r2s)" in common
    assert "fastqc_inputs=()" in fastqc
    assert "expects exactly one R1 and one R2" not in fastqc
