from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
RUN_METRICS_SCRIPT = REPO_ROOT / "workflow" / "scripts" / "illumina_run_metrics.py"
DISPOSITIONS_SCRIPT = REPO_ROOT / "workflow" / "scripts" / "read_dispositions_report.py"


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def _write_fixture_run(run_dir: Path) -> Path:
    reports = run_dir / "Analysis" / "1" / "Data" / "BCLConvert" / "fastq" / "Reports"
    reports.mkdir(parents=True)
    (run_dir / "RunInfo.xml").write_text(
        """<?xml version="1.0"?>
<RunInfo>
  <Run Id="RUN1" Number="1">
    <Flowcell>FC1</Flowcell>
    <Instrument>INST1</Instrument>
    <Reads>
      <Read Number="1" NumCycles="2" IsIndexedRead="N"/>
      <Read Number="2" NumCycles="1" IsIndexedRead="Y"/>
      <Read Number="3" NumCycles="2" IsIndexedRead="N"/>
    </Reads>
    <FlowcellLayout LaneCount="1" SurfaceCount="2" SwathCount="1" TileCount="1"/>
  </Run>
</RunInfo>
""",
        encoding="utf-8",
    )
    (run_dir / "RunParameters.xml").write_text(
        """<?xml version="1.0"?>
<RunParameters>
  <ExperimentName>fixture</ExperimentName>
  <InstrumentType>NovaSeqX</InstrumentType>
  <FlowCellType>10B</FlowCellType>
</RunParameters>
""",
        encoding="utf-8",
    )
    (run_dir / "SampleSheet.csv").write_text(
        "[Header]\nRunName,RUN1\n[Data]\nSample_ID,index,index2\nS1,ACGT,TGCA\n",
        encoding="utf-8",
    )
    (reports / "fastq_list.csv").write_text(
        "RGSM,Lane,Read1File,Read2File\nS1,1,S1_R1.fastq.gz,S1_R2.fastq.gz\n",
        encoding="utf-8",
    )
    (reports / "Quality_Metrics.csv").write_text(
        "\n".join(
            [
                "Lane,SampleID,index,index2,ReadNumber,Yield,YieldQ30,% Q30,Mean Quality Score (PF)",
                "1,S1,ACGT,TGCA,1,20,18,90,35",
                "1,S1,ACGT,TGCA,2,20,18,90,35",
                "1,Undetermined,na,na,1,4,2,50,20",
                "1,Undetermined,na,na,2,4,2,50,20",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    return reports


def _run_illumina_metrics(run_dir: Path, out_dir: Path) -> Path:
    mqc = out_dir / "illumina_run_metrics_mqc.tsv"
    subprocess.run(
        [
            sys.executable,
            str(RUN_METRICS_SCRIPT),
            "--run-dir",
            str(run_dir),
            "--output-dir",
            str(out_dir),
            "--mqc-out",
            str(mqc),
        ],
        cwd=REPO_ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return mqc


def test_illumina_run_metrics_local_fixture_read_equivalents(tmp_path: Path) -> None:
    pd = pytest.importorskip("pandas")
    run_dir = tmp_path / "run"
    _write_fixture_run(run_dir)
    out_dir = tmp_path / "metrics"

    mqc = _run_illumina_metrics(run_dir, out_dir)

    analyzed = pd.read_csv(
        out_dir
        / "raw_metric_tables"
        / "bclconvert_quality_metrics_by_analyzed_sample_lane.tsv",
        sep="\t",
    )
    assert analyzed.loc[0, "SampleID"] == "S1"
    assert analyzed.loc[0, "read_equivalents"] == 20

    undetermined = pd.read_csv(
        out_dir
        / "raw_metric_tables"
        / "bclconvert_quality_metrics_undetermined_by_lane.tsv",
        sep="\t",
    )
    assert undetermined.loc[0, "read_equivalents"] == 4

    artifact_status = pd.read_csv(
        out_dir / "raw_metric_tables" / "artifact_status.tsv", sep="\t"
    )
    assert artifact_status[
        (artifact_status["artifact"] == "Adapter_Metrics.csv")
        & (artifact_status["status"] == "missing")
    ].shape[0] == 1
    assert mqc.exists()
    assert (out_dir / "illumina_run_metrics.html").exists()
    assert (out_dir / "illumina_run_metrics.md").exists()


def test_illumina_run_metrics_missing_required_reports_exact_path(tmp_path: Path) -> None:
    pytest.importorskip("pandas")
    run_dir = tmp_path / "run"
    reports = _write_fixture_run(run_dir)
    (run_dir / "SampleSheet.csv").unlink()
    (reports / "Quality_Metrics.csv").unlink()

    proc = subprocess.run(
        [
            sys.executable,
            str(RUN_METRICS_SCRIPT),
            "--run-dir",
            str(run_dir),
            "--output-dir",
            str(tmp_path / "metrics"),
            "--mqc-out",
            str(tmp_path / "mqc.tsv"),
        ],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
    )

    assert proc.returncode != 0
    assert str(run_dir / "SampleSheet.csv") in proc.stderr
    assert str(reports / "Quality_Metrics.csv") in proc.stderr


def test_read_dispositions_residual_math_and_language(tmp_path: Path) -> None:
    pd = pytest.importorskip("pandas")
    run_dir = tmp_path / "run"
    _write_fixture_run(run_dir)
    metrics_dir = tmp_path / "metrics"
    _run_illumina_metrics(run_dir, metrics_dir)

    samples = tmp_path / "samples.tsv"
    units = tmp_path / "units.tsv"
    alignstats = tmp_path / "alignstats_combo_mqc.tsv"
    out_dir = tmp_path / "dispositions"
    mqc = tmp_path / "read_dispositions_mqc.tsv"

    samples.write_text("SAMPLEID\tSAMPLESOURCE\nS1\tsaliva\n", encoding="utf-8")
    units.write_text(
        "\t".join(
            [
                "RUNID",
                "SAMPLEID",
                "EXPERIMENTID",
                "LANEID",
                "BARCODEID",
                "LIBPREP",
                "SEQ_VENDOR",
                "SEQ_PLATFORM",
            ]
        )
        + "\nRUN1\tS1\tEXP\t1\tBC\tPCR-FREE\tILMN\tNOVASEQ\n",
        encoding="utf-8",
    )
    alignstats.write_text(
        "\t".join(
            [
                "sample",
                "aligner",
                "InputFileName",
                "YieldReads",
                "MappedReads",
                "UnmappedReads",
                "WgsAlignedReads",
                "WgsCalculatedAlignedReads",
                "WgsCovDuplicateReads",
            ]
        )
        + "\n"
        + "\t".join(
            [
                "RUN1-S1-EXP-1-BC-PCR-FREE-ILMN-NOVASEQ.sent",
                "sent",
                "/x/align/sent/dmd/sample.cram",
                "18",
                "15",
                "3",
                "14",
                "12",
                "2",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    subprocess.run(
        [
            sys.executable,
            str(DISPOSITIONS_SCRIPT),
            "--metrics-dir",
            str(metrics_dir / "raw_metric_tables"),
            "--alignstats-combo",
            str(alignstats),
            "--samples-tsv",
            str(samples),
            "--units-tsv",
            str(units),
            "--output-dir",
            str(out_dir),
            "--mqc-out",
            str(mqc),
        ],
        cwd=REPO_ROOT,
        check=True,
        text=True,
        capture_output=True,
    )

    sample_lane = pd.read_csv(out_dir / "sample_lane_dispositions.tsv", sep="\t")
    assert sample_lane.loc[0, "bclconvert_assigned_reads"] == 20
    assert sample_lane.loc[0, "alignment_input_reads"] == 18
    assert sample_lane.loc[0, "not_represented_in_human_aligned_stream_reads"] == 2
    assert sample_lane.loc[0, "human_mapped_pct_of_alignment_input"] == 15 / 18 * 100
    report = (out_dir / "read_dispositions.md").read_text(encoding="utf-8")
    assert "not represented in the human-aligned read stream" in report
    assert "classified as contamination without an independent classifier source" in report
    assert mqc.exists()


def test_illumina_report_rules_config_and_multiqc_contracts() -> None:
    snakefile = _read("workflow/Snakefile")
    rules = _read("workflow/rules/illumina_run_reports.smk")
    final = _read("workflow/rules/multiqc_final_wgs.smk")
    multiqc = _yaml("config/external_tools/multiqc_config.yaml")

    assert 'include: "rules/illumina_run_reports.smk"' in snakefile
    assert "rule produce_illumina_run_metrics:" in rules
    assert "rule produce_read_dispositions:" in rules
    assert "illumina_run_metrics.run_dir is required" in rules
    assert "illumina_run_metrics.aws_profile is required" in rules
    assert "illumina_run_metrics.aws_region is required" in rules
    assert "workflow/scripts/illumina_run_metrics.py" in rules
    assert "workflow/scripts/read_dispositions_report.py" in rules
    assert "other_reports/illumina_run_metrics_mqc.tsv" in rules
    assert "other_reports/read_dispositions_mqc.tsv" in rules

    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        config = _yaml(path)
        assert config["illumina_run_metrics"] == {
            "run_dir": "",
            "aws_profile": "",
            "aws_region": "us-west-2",
        }

    assert 'qc_tool_enabled("illumina_run_metrics", default=False)' in final
    assert 'qc_tool_enabled("read_dispositions", default=False)' in final
    assert "other_reports/illumina_run_metrics_mqc.tsv" in final
    assert "other_reports/read_dispositions_mqc.tsv" in final
    assert multiqc["sp"]["illumina_run_metrics"]["fn"] == (
        "other_reports/illumina_run_metrics_mqc.tsv"
    )
    assert multiqc["sp"]["read_dispositions"]["fn"] == (
        "other_reports/read_dispositions_mqc.tsv"
    )
    assert "illumina_run_metrics" in multiqc["custom_data"]
    assert "read_dispositions" in multiqc["custom_data"]
