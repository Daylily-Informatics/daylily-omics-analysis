from __future__ import annotations

import csv
import importlib.util
import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "workflow/scripts/input_sample_libraries_mqc.py"


def _load_helper():
    spec = importlib.util.spec_from_file_location(
        "input_sample_libraries_mqc_under_test", SCRIPT
    )
    assert spec is not None and spec.loader is not None
    helper_module = importlib.util.module_from_spec(spec)
    sys.modules["input_sample_libraries_mqc_under_test"] = helper_module
    spec.loader.exec_module(helper_module)
    return helper_module


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def test_input_sample_libraries_mqc_joins_samples_and_units_with_comments(
    tmp_path: Path,
) -> None:
    helper_module = _load_helper()
    samples = [
        {
            "SAMPLEID": "HG003",
            "SAMPLESOURCE": "blood",
            "SAMPLECLASS": "research",
            "BIOLOGICAL_SEX": "male",
            "COMMENT": "sample note",
        }
    ]
    units = [
        {
            "RUNID": "RUN007",
            "SAMPLEID": "HG003",
            "EXPERIMENTID": "EXP1",
            "LANEID": "1",
            "BARCODEID": "BC01",
            "LIBPREP": "PCR-FREE",
            "SEQ_VENDOR": "ILMN",
            "SEQ_PLATFORM": "NOVASEQ",
            "ILMN_R1_PATH": "r1.fastq.gz",
            "ILMN_R2_PATH": "r2.fastq.gz",
            "COMMENT": "unit note",
        }
    ]
    metadata = [
        {
            "analysis_unit_uid": "RUN007-HG003-EXP1-1-BC01-PCR-FREE-ILMN-NOVASEQ"
        }
    ]
    output = tmp_path / "input_sample_libraries_mqc.tsv"

    fieldnames, written_rows = helper_module.write_input_sample_libraries_mqc(
        output,
        metadata=metadata,
        sample_records=samples,
        unit_records=units,
        added_by_snakemake=False,
    )

    assert fieldnames[:3] == [
        "analysis_unit_id",
        "Sample",
        "added_by_snakemake",
    ]
    assert written_rows[0]["unit_comment"] == "unit note"
    assert written_rows[0]["sample_comment"] == "sample note"
    rows = _read_tsv(output)
    assert rows == [
        {
            "analysis_unit_id": "RUN007-HG003-EXP1-1-BC01-PCR-FREE-ILMN-NOVASEQ",
            "Sample": "RUN007-HG003-EXP1-1-BC01-PCR-FREE-ILMN-NOVASEQ",
            "added_by_snakemake": "false",
            "runid": "RUN007",
            "sampleid": "HG003",
            "experimentid": "EXP1",
            "laneid": "1",
            "barcodeid": "BC01",
            "libprep": "PCR-FREE",
            "seq_vendor": "ILMN",
            "seq_platform": "NOVASEQ",
            "ilmn_r1_path": "r1.fastq.gz",
            "ilmn_r2_path": "r2.fastq.gz",
            "unit_comment": "unit note",
            "samplesource": "blood",
            "sampleclass": "research",
            "biological_sex": "male",
            "sample_comment": "sample note",
        }
    ]


def test_comment_is_declared_optional_in_sample_and_unit_schemas() -> None:
    for path in (
        REPO_ROOT / "workflow/schemas/samples.schema.yaml",
        REPO_ROOT / "workflow/schemas/units.schema.yaml",
    ):
        schema = yaml.safe_load(path.read_text(encoding="utf-8"))
        assert schema["properties"]["COMMENT"]["type"] == "string"
        assert "COMMENT" not in schema["required"]
