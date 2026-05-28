from __future__ import annotations

from pathlib import Path

from daylily_omics_analysis.pipeline_reports import (
    RuleSummary,
    parse_rule_summaries,
    write_mermaid,
    write_snapshot,
)


def test_pipeline_details_and_mermaid_snapshot_are_written(tmp_path: Path) -> None:
    workflow = tmp_path / "workflow"
    rules = workflow / "rules"
    rules.mkdir(parents=True)
    (rules / "example.smk").write_text(
        """
rule align_reads:
    output:
        "out.bam"
    shell:
        "samtools view --version > {output}"
""",
        encoding="utf-8",
    )
    config = tmp_path / "config"
    config.mkdir()
    (config / "samples.tsv").write_text("sample\nHG002\nHG003\n", encoding="utf-8")
    renderer = tmp_path / "mmdc"
    renderer.write_text(
        """#!/usr/bin/env bash
out=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf '%s\\n' '%PDF-1.4 test' > "$out"
""",
        encoding="utf-8",
    )
    renderer.chmod(0o755)

    mmd, pdf, details = write_snapshot(
        analysis_root=tmp_path,
        workflow_root=workflow,
        output_dir=tmp_path,
        genome_build="hg38",
        state="planned",
        command="bin/day_run produce_alignstats",
        renderer=str(renderer),
        write_details=True,
    )

    assert details == tmp_path / "pipeline_details.md"
    assert "align_reads" in details.read_text(encoding="utf-8")
    assert "samtools" in details.read_text(encoding="utf-8")
    assert "samples: HG002, HG003" in mmd.read_text(encoding="utf-8")
    assert pdf.read_text(encoding="utf-8").startswith("%PDF")


def test_parse_rule_summaries_requires_rules_directory(tmp_path: Path) -> None:
    try:
        parse_rule_summaries(tmp_path / "missing")
    except Exception as exc:
        assert "Rules directory is missing" in str(exc)
    else:  # pragma: no cover
        raise AssertionError("expected missing rules directory to fail")


def test_mermaid_snapshot_does_not_cap_rule_count(tmp_path: Path) -> None:
    config = tmp_path / "config"
    config.mkdir()
    (config / "samples.tsv").write_text("sample\nHG002\n", encoding="utf-8")
    output = tmp_path / "workflow.mmd"
    summaries = [
        RuleSummary(
            name=f"rule_{idx:03d}",
            command=f"tool_{idx:03d} --input sample",
            tool_names=(f"tool_{idx:03d}",),
            tool_versions={},
        )
        for idx in range(1, 66)
    ]

    write_mermaid(
        summaries=summaries,
        analysis_root=tmp_path,
        genome_build="hg38",
        state="planned",
        output_path=output,
    )

    text = output.read_text(encoding="utf-8")
    assert "rule_001" in text
    assert "rule_040" in text
    assert "rule_065" in text
    assert text.count(':::rule') == 65
