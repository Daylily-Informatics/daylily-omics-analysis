from __future__ import annotations

import csv
import re
from pathlib import Path
from xml.etree import ElementTree

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


ULTIMA_SECTIONS = {
    "ultima_run_inventory": ("Ultima Run Inventory", "dayoa_input_demux_read_qc"),
    "ultima_demux_summary": ("Ultima Demux / Barcode Summary", "dayoa_input_demux_read_qc"),
    "ultima_trimmer_stats": ("Ultima Trimmer Stats", "dayoa_input_demux_read_qc"),
    "ultima_trimmer_failures": ("Ultima Trimmer Failure Codes", "dayoa_input_demux_read_qc"),
    "ultima_flowq_summary": ("Ultima FlowQ Summary", "dayoa_input_demux_read_qc"),
    "ultima_snvq_summary": ("Ultima SNVQ Summary", "dayoa_input_demux_read_qc"),
    "ultima_coverage_summary": ("Ultima Coverage Summary", "dayoa_alignment_coverage"),
    "ultima_picard_summary": ("Ultima Picard / Basic Run Metrics", "dayoa_alignment_coverage"),
    "ultima_contamination": ("Ultima Contamination / Sample Swap", "dayoa_variant_benchmark_annotation"),
    "ultima_upload_status": ("Ultima Upload Status", "dayoa_workflow_reporting"),
    "ultima_unmatched": ("Ultima Unmatched Outputs", "dayoa_input_demux_read_qc"),
}


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def test_ultima_run_qc_spec_package_exists_and_preserves_boundaries() -> None:
    paths = [
        "docs/specs/ultima_run_qc_requirements.md",
        "docs/specs/ugrun_cli_contract.md",
        "docs/specs/ugrun_metrics_schema.md",
        "docs/specs/ugrun_multiqc_contract.md",
        "docs/workflows/ultima_run_qc.md",
        "docs/plans/20260526T074804Z_ultima_run_qc_native_multiqc_ledger.md",
    ]
    for path in paths:
        text = _read(path)
        assert "Ultima" in text or "ugrun" in text

    requirements = _read("docs/specs/ultima_run_qc_requirements.md")
    assert "must not create clinical release decisions" in requirements
    assert "Silent empty reports when required evidence is missing" in requirements
    assert "missing required files" in requirements
    assert "Do not equate FlowQ/SNVQ with Illumina Q-score" in requirements


def test_ultima_multiqc_custom_sections_are_registered() -> None:
    cfg = yaml.safe_load(_read("config/external_tools/multiqc_config.yaml"))
    custom = cfg["custom_data"]
    sp = cfg["sp"]
    order = cfg["report_section_order"]
    module_order = cfg["module_order"]

    for section_id, (section_name, parent_id) in ULTIMA_SECTIONS.items():
        assert section_id in custom
        assert custom[section_id]["id"] == section_id
        assert custom[section_id]["section_name"] == section_name
        assert custom[section_id]["parent_id"] == parent_id
        assert section_id in sp
        assert sp[section_id]["fn"].startswith("run_qc/ultima/**/")
        assert sp[section_id]["fn"].endswith("_mqc.tsv")
        assert section_id in order
        assert section_id in module_order


def test_ultima_sample_identifier_contract_and_fixture_rows() -> None:
    spec = _read("docs/specs/ugrun_multiqc_contract.md")
    assert "<run_id>.<barcode_id>.<sample_id>" in spec
    assert "<run_id>.unmatched.<file_kind>" in spec
    assert "[A-Za-z0-9._+-]" in spec

    fixture = REPO_ROOT / ".test_data/data/ultima_run_qc/ultima_demux_summary_mqc.tsv"
    with fixture.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        assert reader.fieldnames is not None
        assert reader.fieldnames[0] == "Sample"
        rows = list(reader)

    assert rows
    for row in rows:
        sample = row["Sample"]
        assert sample not in {"R1", "R2", "metrics"}
        assert re.fullmatch(r"[A-Za-z0-9._+-]+", sample), sample
        assert sample.startswith(f"{row['run_id']}.{row['barcode_id']}.{row['sample_id']}")


def test_synthetic_libraryinfo_fixture_preserves_unknown_fields() -> None:
    xml_path = REPO_ROOT / ".test_data/data/ultima_run_qc/602202_LibraryInfo.xml"
    root = ElementTree.parse(xml_path).getroot()

    assert root.attrib["RunId"] == "602202"
    samples = list(root.findall(".//Sample"))
    assert len(samples) == 2
    assert samples[0].attrib["Index_Label"] == "Z0157"
    assert samples[0].attrib["unknown_fake_field"] == "preserve_me"


def test_ultima_run_qc_remains_outside_routine_final_multiqc() -> None:
    final_multiqc = _read("workflow/rules/multiqc_final_wgs.smk")
    ops = _read("docs/ops/multiqc_qc_targets.md")

    assert "run_qc/ultima" not in final_multiqc
    assert "explicitly enables Ultima run QC" in ops
    assert "parser-backed run-QC target" in ops
