from __future__ import annotations

import csv
import importlib.util
from pathlib import Path
from types import SimpleNamespace


REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_contam_identity_parser_preserves_tool_evidence(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/compile_contam_identity_mqc.py",
        "compile_contam_identity_mqc_under_test",
    )
    root = tmp_path / "results/day/hg38"
    contamination = root / "other_reports/contamination_mqc.tsv"
    contamination.parent.mkdir(parents=True)
    contamination.write_text(
        "Sample\tbase_sample\tsample_id\texternal_sample_id\taligner\tdeduper\t"
        "panel_id\tpanel_label\ttool\tmethod\tcontamination_fraction\t"
        "contamination_pct\tci_low_fraction\tci_high_fraction\t"
        "unknown_contamination_fraction\tunknown_contamination_pct\tsite_count\t"
        "read_count\tmean_depth\tsvd_prefix\tsource_path\tstatus\n"
        "HG003.sent.dmd\tHG003\tHG003\tEXT-HG003\tsent\tdmd\t\t\tgatk\t"
        "freemix\t0.01\t1.0\t\t\t\t\t100\t200\t2\t\tgatk.tsv\tok\n",
        encoding="utf-8",
    )
    ngs = root / "other_reports/contam_identity/sent/dmd/ngstroublefinder/qcReport.tsv"
    ngs.parent.mkdir(parents=True)
    ngs.write_text(
        "Sample_Name\tcontamination\tsex\nHG003.sent.dmd\t0.02\tFemale\n",
        encoding="utf-8",
    )
    haplo = (
        root
        / "HG003/align/sent/dmd/alignqc/contam_identity/haplocheck/bam/"
        / "HG003.sent.dmd.haplocheck.contamination.txt"
    )
    haplo.parent.mkdir(parents=True)
    haplo.write_text(
        "Sample\tContamination Status\tContamination Level\tDistance\tSample Coverage\n"
        "HG003\tYES\t0.03\t8\t100\n",
        encoding="utf-8",
    )
    read_haps = (
        root
        / "HG003/align/sent/dmd/snv/sentd/contam_identity/read_haps/"
        / "HG003.sent.dmd.sentd.read_haps.txt"
    )
    read_haps.parent.mkdir(parents=True)
    read_haps.write_text(
        "SNP_PAIRS ERROR_PAIRS DOUBLE_ERROR_PAIR_COUNT DOUBLE_ERROR_FRACTION "
        "REL_ERROR_FRACTION NONSENSE_FRACTION PASS_FAIL REASON\n"
        "100 2 1 0.01 0.02 0.001 FAIL CONTAMINATION\n",
        encoding="utf-8",
    )
    identity_out = tmp_path / "contam_identity_mqc.tsv"
    ngs_out = tmp_path / "ngstroublefinder_mqc.tsv"
    haplo_out = tmp_path / "haplocheck_mtdna_mqc.tsv"
    read_haps_out = tmp_path / "read_haps_mqc.tsv"

    module.compile_reports(
        SimpleNamespace(
            sample_map_json='{"HG003":"EXT-HG003"}',
            contam_identity_output=str(identity_out),
            ngstroublefinder_output=str(ngs_out),
            haplocheck_output=str(haplo_out),
            read_haps_output=str(read_haps_out),
            contamination=[str(contamination)],
            ngstroublefinder=[str(ngs)],
            haplocheck=[str(haplo)],
            read_haps=[str(read_haps)],
        )
    )

    with read_haps_out.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    assert rows == [
        {
            "Sample": "HG003.sent.dmd.sentd",
            "base_sample": "HG003",
            "sample_id": "HG003",
            "external_sample_id": "EXT-HG003",
            "aligner": "sent",
            "deduper": "dmd",
            "snv_caller": "sentd",
            "snp_pairs": "100",
            "error_pairs": "2",
            "double_error_pair_count": "1",
            "double_error_fraction": "0.01",
            "rel_error_fraction": "0.02",
            "nonsense_fraction": "0.001",
            "pass_fail": "FAIL",
            "reason": "CONTAMINATION",
            "source_path": str(read_haps),
        }
    ]

    with identity_out.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    assert {row["tool"] for row in rows} >= {
        "gatk",
        "ngstroublefinder",
        "haplocheck",
        "read_haps",
    }
    read_haps_rows = [row for row in rows if row["tool"] == "read_haps"]
    assert read_haps_rows[0]["tool_pass_fail"] == "FAIL"
    assert read_haps_rows[0]["tool_reason"] == "CONTAMINATION"


def test_contam_identity_contracts_are_explicit() -> None:
    rules = (REPO_ROOT / "workflow/rules/contam_identity.smk").read_text(
        encoding="utf-8"
    )
    parser = (
        REPO_ROOT / "workflow/scripts/compile_contam_identity_mqc.py"
    ).read_text(encoding="utf-8")
    snakefile = (REPO_ROOT / "workflow/Snakefile").read_text(encoding="utf-8")
    assert 'include: "rules/contam_identity.smk"' in snakefile
    assert 'include: "rules/verifybamid2_contam.smk"' not in [
        line.strip() for line in snakefile.splitlines() if line.strip().startswith("include:")
    ]
    for expected in (
        "contam_identity.primary_snv_caller",
        "haplocheck.input_modes",
        "read_haps.reliable_snp_file",
        "produce_global_contam_check",
    ):
        assert expected in rules
    for retired in (
        "rule ngstroublefinder_contam_identity:",
        "rule produce_ngstroublefinder_contam_identity:",
        "ngstroublefinder_mqc.tsv",
        "rule charr_contam_identity:",
        "rule produce_charr_contam_identity:",
        "charr_mqc.tsv",
        "charr.ref_af_resource",
    ):
        assert retired not in rules
    assert "tool_pass_fail" in parser
    assert "--ngstroublefinder-output" in parser
