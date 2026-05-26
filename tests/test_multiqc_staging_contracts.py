from __future__ import annotations

import csv
import importlib.util
import re
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


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


def _rule_block(text: str, rule_name: str) -> str:
    match = re.search(
        rf"^rule {re.escape(rule_name)}:.*?(?=^rule |\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    assert match is not None, rule_name
    return match.group(0)


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def test_final_stage_alias_is_concrete_and_targets_final_stage_done() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")
    alias = _rule_block(text, "produce_multiqc_stage_final")

    assert "produce_multiqc_stage_final," in text
    assert 'MDIR + "reports/multiqc_inputs/final/.stage.done"' in alias
    assert "{report_stage}" not in alias
    assert "DAY_final_multiqc.html" not in alias


def test_report_rules_guard_and_ignore_mqc_logs() -> None:
    text = _read("workflow/rules/multiqc_final_wgs.smk")

    for rule_name in (
        "multiqc_seq_data",
        "multiqc_alignment",
        "multiqc_variants",
        "multiqc_final_wgs",
    ):
        block = _rule_block(text, rule_name)
        assert "workflow/scripts/multiqc_log_guard.py" in block
        assert '--ignore "*/other_reports/logs/*"' in block
        assert '--ignore "other_reports/logs/*"' in block
        assert '--ignore "*_mqc.log"' in block


def test_stage_multiqc_inputs_does_not_manifest_mqc_logs(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_staging_contracts_under_test",
    )
    input_root = tmp_path / "results/day/hg38"
    log_path = input_root / "other_reports/logs/alignment_qc_outputs_mqc.log"
    output_dir = input_root / "reports/multiqc_inputs/final"
    manifest = output_dir / "manifest.tsv"
    log_path.parent.mkdir(parents=True)
    log_path.write_text("metric\tvalue\n", encoding="utf-8")

    stager = module.Stager(input_root, output_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, log_path)
    stager.finish()

    assert not stager.rows
    assert _read_tsv(manifest) == []
    assert not list(output_dir.rglob("*_mqc.log"))


def test_stage_multiqc_inputs_stages_native_kraken2_reports(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_kraken_contracts_under_test",
    )
    input_root = tmp_path / "results/day/hg38"
    report_path = (
        input_root
        / "HG002/align/sent/dmd/alignqc/unmapped_metagenomics"
        / "HG002.sent.dmd.kraken2.quick.report.txt"
    )
    output_dir = input_root / "reports/multiqc_inputs/final"
    manifest = output_dir / "manifest.tsv"
    report_path.parent.mkdir(parents=True)
    report_path.write_text("100.00\t10\t10\tR\t1\troot\n", encoding="utf-8")

    stager = module.Stager(input_root, output_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, report_path)
    stager.finish()

    staged = output_dir / "native/kraken/HG002.sent.dmd.kraken2.quick.report.txt"
    assert staged.read_text(encoding="utf-8") == report_path.read_text(
        encoding="utf-8"
    )
    rows = _read_tsv(manifest)
    assert rows == [
        {
            "Sample": "HG002.sent.dmd",
            "module": "kraken",
            "stage": "alignment",
            "base_sample": "HG002",
            "aligner": "sent",
            "deduper": "dmd",
            "caller": "",
            "input_kind": "kraken2_report",
            "source_path": str(report_path),
            "staged_path": str(staged),
            "group_id": str(report_path),
        }
    ]


def test_stage_multiqc_inputs_stages_ganon2_sources_from_custom_rows(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_ganon2_contracts_under_test",
    )
    input_root = tmp_path / "results/day/hg38"
    ganon_dir = input_root / "HG002/align/sent/dmd/alignqc/unmapped_metagenomics"
    report_path = ganon_dir / "HG002.sent.dmd.ganon2.quick.tre"
    rep_path = ganon_dir / "HG002.sent.dmd.ganon2.quick.rep"
    mqc_path = input_root / "other_reports/unmapped_metagenomics_ganon2_mqc.tsv"
    output_dir = input_root / "reports/multiqc_inputs/final"
    manifest = output_dir / "manifest.tsv"
    ganon_dir.mkdir(parents=True)
    mqc_path.parent.mkdir(parents=True)
    report_path.write_text(
        "root\t1\t1\troot\t0\t0\t3\t3\t75.00000\n",
        encoding="utf-8",
    )
    rep_path.write_text(
        "#total_classified\t3\n#total_unclassified\t1\n",
        encoding="utf-8",
    )
    mqc_path.write_text(
        "\t".join(
            [
                "Sample",
                "base_sample",
                "aligner",
                "deduper",
                "classifier",
                "ganon2_report",
                "ganon2_rep",
            ]
        )
        + "\n"
        + "\t".join(
            [
                "HG002.sent.dmd",
                "HG002",
                "sent",
                "dmd",
                "ganon2",
                str(report_path),
                str(rep_path),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    stager = module.Stager(input_root, output_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, mqc_path)
    stager.finish()

    staged_report = output_dir / "native/ganon2/HG002.sent.dmd.ganon2.quick.tre"
    staged_rep = output_dir / "native/ganon2/HG002.sent.dmd.ganon2.quick.rep"
    assert staged_report.read_text(encoding="utf-8") == report_path.read_text(
        encoding="utf-8"
    )
    assert staged_rep.read_text(encoding="utf-8") == rep_path.read_text(
        encoding="utf-8"
    )
    rows = _read_tsv(manifest)
    assert {row["input_kind"] for row in rows} == {
        "custom_mqc_row",
        "ganon2_tree_report",
        "ganon2_rep",
    }
    assert {row["module"] for row in rows} == {
        "unmapped_metagenomics_ganon2",
        "ganon2",
    }


def test_stage_multiqc_inputs_stages_sourmash_sources_from_custom_rows(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_sourmash_contracts_under_test",
    )
    input_root = tmp_path / "results/day/hg38"
    sourmash_dir = input_root / "HG002/align/sent/dmd/alignqc/unmapped_metagenomics"
    sig_path = sourmash_dir / "HG002.sent.dmd.sourmash.sig"
    gather_path = sourmash_dir / "HG002.sent.dmd.sourmash.gather.csv"
    mqc_path = input_root / "other_reports/unmapped_metagenomics_sourmash_mqc.tsv"
    output_dir = input_root / "reports/multiqc_inputs/final"
    manifest = output_dir / "manifest.tsv"
    sourmash_dir.mkdir(parents=True)
    mqc_path.parent.mkdir(parents=True)
    sig_path.write_text("{\"class\":\"sourmash_signature\"}\n", encoding="utf-8")
    gather_path.write_text(
        "unique_intersect_bp,intersect_bp,f_unique_to_query,f_unique_weighted,"
        "filename,name,md5,gather_result_rank,query_bp,ksize,moltype,scaled,"
        "query_n_hashes\n",
        encoding="utf-8",
    )
    mqc_path.write_text(
        "\t".join(
            [
                "Sample",
                "base_sample",
                "aligner",
                "deduper",
                "classifier",
                "sourmash_signature",
                "sourmash_gather_csv",
            ]
        )
        + "\n"
        + "\t".join(
            [
                "HG002.sent.dmd",
                "HG002",
                "sent",
                "dmd",
                "sourmash_gather",
                str(sig_path),
                str(gather_path),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    stager = module.Stager(input_root, output_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, mqc_path)
    stager.finish()

    staged_sig = output_dir / "native/sourmash/HG002.sent.dmd.sourmash.sig"
    staged_gather = output_dir / "native/sourmash/HG002.sent.dmd.sourmash.gather.csv"
    assert staged_sig.read_text(encoding="utf-8") == sig_path.read_text(
        encoding="utf-8"
    )
    assert staged_gather.read_text(encoding="utf-8") == gather_path.read_text(
        encoding="utf-8"
    )
    rows = _read_tsv(manifest)
    assert {row["input_kind"] for row in rows} == {
        "custom_mqc_row",
        "sourmash_signature",
        "sourmash_gather_csv",
    }
    assert {row["module"] for row in rows} == {
        "unmapped_metagenomics_sourmash",
        "sourmash",
    }


def test_multiqc_log_guard_renames_zero_byte_and_rejects_nonempty_mqc_logs(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/multiqc_log_guard.py",
        "multiqc_log_guard_staging_contracts_under_test",
    )
    log_dir = tmp_path / "other_reports/logs"
    log_dir.mkdir(parents=True)

    empty_log = log_dir / "sequence_qc_outputs_mqc.log"
    empty_log.touch()
    renamed = module.guard_log_dir(log_dir)

    assert renamed == [log_dir / "sequence_qc_outputs_legacy_custom_data.log"]
    assert not empty_log.exists()

    bad_log = log_dir / "alignment_qc_outputs_mqc.log"
    bad_log.write_text("metric\tvalue\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="non-empty \\*_mqc.log"):
        module.guard_log_dir(log_dir)


def test_relatedness_report_runs_with_snakemake_script_object(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/relatedness_report.py",
        "relatedness_report_staging_contracts_under_test",
    )
    manifest = tmp_path / "relatedness_manifest.tsv"
    manifest.write_text(
        "sample_id\tpath\tpath_type\tsex\tfamily_id\texternal_sample_id\n"
        "HG002\t/fsx/HG002.cram\tcram\tmale\ttrio\tKID\n"
        "HG003\t/fsx/HG003.cram\tcram\tmale\ttrio\tDAD\n",
        encoding="utf-8",
    )
    pairs = tmp_path / "cohort.pairs.tsv"
    pairs.write_text(
        "sample_a\tsample_b\trelatedness\tibs0\n"
        "KID\tDAD\t0.50\t0.5\n",
        encoding="utf-8",
    )
    output_pairs = tmp_path / "relatedness_pairs_classified.tsv"
    output_summary = tmp_path / "relatedness_summary.tsv"
    output_html = tmp_path / "relatedness_report.html"
    snakemake = SimpleNamespace(
        input=SimpleNamespace(
            manifest=str(manifest),
            pairs=str(pairs),
        ),
        output=SimpleNamespace(
            pairs_classified=str(output_pairs),
            summary=str(output_summary),
            html=str(output_html),
        ),
        params=SimpleNamespace(
            expected="",
            thresholds={},
        ),
    )

    module.run_from_snakemake(snakemake)

    classified = _read_tsv(output_pairs)
    summary = _read_tsv(output_summary)
    assert classified[0]["sample_a"] == "HG002"
    assert classified[0]["sample_b"] == "HG003"
    assert classified[0]["relationship"] == "parent_child"
    assert summary == [
        {"relationship": "parent_child", "status": "NA", "pair_count": "1"}
    ]
    assert "Relatedness QC" in output_html.read_text(encoding="utf-8")
