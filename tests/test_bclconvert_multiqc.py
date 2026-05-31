from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = REPO_ROOT / ".test_data" / "data" / "bclconvert"


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def test_bclconvert_rule_exports_metrics_to_genome_build_multiqc_dir() -> None:
    rule = _read("workflow/rules/bclconvert.smk")
    common = _read("workflow/rules/common.smk")
    multiqc = _read("workflow/rules/multiqc_final_wgs.smk")

    assert 'BCL_RUN_CONTEXT = run_context_for_platform("ILMN", require=False)' in rule
    assert 'BCL_RUNTIME_VERSION = "4.0.3"' in rule
    assert "BCL_TARGET_REQUESTED = bool(_requested_targets() & BCL_BOOTSTRAP_TARGETS)" in rule
    assert 'BCL_ROOT = (' in rule
    assert 'f"{BCL_OUTPUT_ROOT}/bclconvert"' in rule
    assert 'f"{BCL_ROOT}/fastqs"' in rule
    assert 'BCL_MQC_DIR = f"{BCL_ROOT}/multiqc_inputs" if BCL_RUN_CONTEXT is not None else f"{MDIR}other_reports"' in rule
    assert 'f"{BCL_ROOT}/bclconvert_metrics_mqc.done"' in rule
    assert "multiqc_report.html" in rule
    assert "generated.units.tsv" in rule
    assert "BCL_BENCH_DIR" in rule
    assert "bcl_extra_args={params.extra_args:q}" in rule
    assert "DAYOA_BCLCONVERT_LANE_SPLIT = True" in rule
    assert 'BCL_MERGE_LANE_FASTQS = _bool(BCLCFG.get("merge_lane_fastqs", False), False)' in rule
    assert "rule run_bclconvert_lane:" in rule
    assert "workflow/scripts/run_bclconvert_lane.sh" in rule
    assert "workflow/scripts/merge_bclconvert_lanes.py" in rule
    assert "run_bclconvert_lane_fastqs_ready" in rule
    assert "BCL_FASTQ_LIST_INPUT_FILES = BCL_LANE_FASTQ_LIST_FILES" in rule
    lane_helper = _read("workflow/scripts/run_bclconvert_lane.sh")
    samplesheet_helper = _read("workflow/scripts/prepare_bclconvert_lane_samplesheet.py")
    assert "--bcl-only-lane" in lane_helper
    assert "--output-legacy-stats" in lane_helper
    assert "--num-unknown-barcodes-reported" in lane_helper
    assert "--bind /fsx:/fsx" in lane_helper
    assert "ALLOWED_SETTINGS" in samplesheet_helper
    assert "BCL_LANE_ROOT = Path(BCL_RUN_DIR)" in rule
    assert "sample_sheet_settings_json=BCL_SAMPLE_SHEET_SETTINGS_JSON" in rule
    assert '"BarcodeMismatchesIndex1": "barcode_mismatches_index1"' in rule
    assert '"BarcodeMismatchesIndex2": "barcode_mismatches_index2"' in rule
    assert "BCL_OUTPUT_LEGACY_STATS" in rule
    assert "BCL_NUM_UNKNOWN_BARCODES_REPORTED" in rule
    assert "exclusive=\"--exclusive\"" in rule
    assert "rule bclconvert_demux_fastq_qc:" in rule
    assert "workflow/scripts/prepare_bclconvert_demux_fastqc_inputs.py" in rule
    assert "BCL_DEMUX_FASTQC_MQC" in rule
    assert 'FASTQC_ENV = "../envs/fastqc_v0.1.yaml"' in rule
    assert "BCL_STAGING_MODE" not in rule
    assert "Copying mounted BCL files with sharded cp" not in rule
    assert "cp -aL --sparse=always" not in rule
    assert "aws s3 sync" not in rule
    assert '--seq-platform-override "$seq_platform_override"' in rule
    for rule_name in (
        "bclconvert_validate_inputs",
        "run_bclconvert",
        "bclconvert_generate_units_tsv",
        "bclconvert_metrics_summary",
        "bclconvert_demux_fastq_qc",
        "bclconvert_metrics_multiqc_exports",
        "multiqc_bclconvert",
    ):
        block = rule[rule.index(f"rule {rule_name}:") :]
        block = block.split("\nrule ", 1)[0]
        assert 'cluster_sample="' in block, rule_name
    assert "-m bclconvert" in rule
    assert "-m fastqc" in rule
    assert "-m custom_content" in rule
    assert "rule bclconvert_metrics_multiqc_exports:" in rule
    assert "workflow/scripts/bclconvert_metrics_to_multiqc.py" in rule
    assert "bclconvert_demux_mqc.tsv" in rule
    assert "bclconvert_unknown_barcodes_mqc.tsv" in rule
    assert "bclconvert_index_hopping_mqc.tsv" in rule
    assert "bclconvert_fastq_manifest_mqc.tsv" in rule
    assert "bclconvert_demux_fastqc_manifest_mqc.tsv" in rule
    assert "bclconvert_lane_summary_mqc.tsv" in rule
    assert "rule produce_bclconvert_metrics:" in rule
    assert "rule produce_bclconvert_multiqc:" in rule
    assert '.get("bclconvert", {})' in rule
    assert 'config/external_tools/multiqc_config.yaml' in rule

    assert '"produce_bclconvert_metrics"' in common
    assert '"produce_bclconvert_multiqc"' in common
    assert '"produce_illumina_run_qc_and_bclconvert"' in common
    assert 'if bootstrap_unit_context and str(row.get("analysis_unit_uid", "")) == str(' in common
    assert "is_bcl_bootstrap_sample = bootstrap_unit_context" in common
    assert "if not is_bcl_bootstrap_sample and any(_bad_token(t)" in common
    assert 'return "na", "na"' in common
    assert "def _bclconvert_enabled_for_multiqc" in common
    assert 'qc_tool_enabled("bclconvert", default=False)' in multiqc
    assert 'MDIR + "other_reports/bclconvert_metrics_mqc.done"' in multiqc


def test_runs_tsv_parser_contract_is_strict_and_run_scoped() -> None:
    common = _read("workflow/rules/common.smk")

    for column in (
        "RUNID",
        "PLATFORM",
        "RUN_DIR",
        "SOURCE_S3_URI",
        "MOUNT_ID",
        "SAMPLE_SHEET",
        "BASECALLING_STATE",
        "RUN_STATUS",
        "OUTPUT_ROOT",
        "REGION",
        "PROFILE",
    ):
        assert f'"{column}"' in common

    assert "RUN_CONTEXT_REQUIRED_COLUMNS" in common
    assert "results/runs/{normalized['RUNID']}" in common
    assert "run_context_for_platform" in common
    assert "config/runs.tsv is missing required column" in common
    assert "PROFILE for RUNID={normalized['RUNID']} is required for S3 mode" in common


def test_bclconvert_custom_data_is_registered_for_multiqc() -> None:
    config = _yaml("config/external_tools/multiqc_config.yaml")
    for key in (
        "bclconvert_demux",
        "bclconvert_lane_summary",
        "bclconvert_fastq_manifest",
        "bclconvert_demux_fastqc_manifest",
        "bclconvert_unknown_barcodes",
        "bclconvert_index_hopping",
    ):
        assert key in config["custom_data"]
        assert key in config["sp"]
        assert config["custom_data"][key]["file_format"] == "tsv"
        assert config["custom_data"][key]["plot_type"] == "table"

    for path in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        profile = _yaml(path)
        assert profile["multiqc"]["bclconvert"]["config_yaml"] == "config/external_tools/multiqc_config.yaml"
        assert profile["multiqc"]["bclconvert"]["env_yaml"] == "../envs/multiqc_v0.1.yaml"
        assert profile["bclconvert"]["fastq_gzip_compression_level"] == 1
        assert profile["bclconvert"]["barcode_mismatches_index1"] == 0
        assert profile["bclconvert"]["barcode_mismatches_index2"] == 0
        assert profile["bclconvert"]["merge_lane_fastqs"] is False
        assert profile["bclconvert"]["output_legacy_stats"] is True
        assert "demux_qc_threads" in profile["bclconvert"]
        assert "demux_qc_mem_mb" in profile["bclconvert"]
        assert "staging_mode" not in profile["bclconvert"]
        assert "scratch_size_multiplier" not in profile["bclconvert"]

    slurm_bcl = _yaml("config/day_profiles/slurm/templates/rule_config.yaml")["bclconvert"]
    assert slurm_bcl["threads"] == 192
    assert slurm_bcl["mem_mb"] == 360000
    assert slurm_bcl["partition"] == "i192mem,i192bigmem"
    assert slurm_bcl["parallel_tiles"] == 24
    assert slurm_bcl["conversion_threads"] == 4
    assert slurm_bcl["compression_threads"] == 64
    assert slurm_bcl["decompression_threads"] == 32
    assert slurm_bcl["shared_thread_odirect_output"] is True
    assert slurm_bcl["demux_qc_threads"] == 32
    assert slurm_bcl["demux_qc_mem_mb"] == 64000


def test_lane_optional_bclconvert_samplesheet_generates_units_for_each_fastq_lane(
    tmp_path: Path,
) -> None:
    sample_sheet = tmp_path / "SampleSheet.csv"
    sample_sheet.write_text(
        "\n".join(
            [
                "[Header],",
                "FileFormatVersion,2",
                "RunName,20260514_ILMN_Altair_Run_3",
                "InstrumentPlatform,NovaSeqXSeries",
                "",
                "[Reads]",
                "Read1Cycles,151",
                "Read2Cycles,151",
                "Index1Cycles,10",
                "Index2Cycles,10",
                "",
                "[BCLConvert_Settings]",
                "SoftwareVersion,4.3.16",
                "OverrideCycles,Y151;I10;I10;Y151",
                "GenerateFastqcMetrics,true",
                "",
                "[BCLConvert_Data]",
                "Sample_ID,Index,Index2",
                "HG003-a,GAGTAATATA,CCGACCGTGA",
                "NTC,AATTCGACCT,AATATGCAAC",
                "",
            ]
        ),
        encoding="utf-8",
    )
    samples = tmp_path / "samples.tsv"
    samples.write_text(
        "\n".join(
            [
                "SAMPLEID\tSAMPLESOURCE\tSAMPLECLASS\tBIOLOGICAL_SEX\tCONCORDANCE_CONTROL_PATH\tIS_POSITIVE_CONTROL\tIS_NEGATIVE_CONTROL\tSAMPLE_TYPE\tTUM_NRM_SAMPLEID_MATCH\tEXTERNAL_SAMPLE_ID\tN_X\tN_Y\tTRUTH_DATA_DIR",
                "HG003-a\tblood\tresearch\tunknown\tna\tfalse\tfalse\tblood\tna\tHG003-a\tna\tna\tna",
                "NTC\tcontrol\tcontrol\tunknown\tna\tfalse\ttrue\tcontrol\tna\tNTC\tna\tna\tna",
                "",
            ]
        ),
        encoding="utf-8",
    )
    normalized = tmp_path / "normalized.SampleSheet.csv"
    rows_tsv = tmp_path / "samplesheet_rows.tsv"
    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "parse_bclconvert_samplesheet.py"),
            "--sample-sheet",
            str(sample_sheet),
            "--samples-tsv",
            str(samples),
            "--normalized-out",
            str(normalized),
            "--rows-out",
            str(rows_tsv),
            "--runtime-version",
            "4.0.3",
        ],
        check=True,
    )

    parsed_rows = _read_tsv(rows_tsv)
    assert {row["LANE"] for row in parsed_rows} == {"*"}
    normalized_text = normalized.read_text(encoding="utf-8")
    assert "SoftwareVersion,4.0.3" in normalized_text
    assert "GenerateFastqcMetrics" not in normalized_text

    fastq_list = tmp_path / "fastq_list.csv"
    fastq_list.write_text(
        "\n".join(
            [
                "RGID,RGSM,RGLB,Lane,Read1File,Read2File",
                "RG001,HG003-a,HG003-a,1,/tmp/HG003-a_L001_R1_001.fastq.gz,/tmp/HG003-a_L001_R2_001.fastq.gz",
                "RG002,HG003-a,HG003-a,2,/tmp/HG003-a_L002_R1_001.fastq.gz,/tmp/HG003-a_L002_R2_001.fastq.gz",
                "RGUND,Undetermined,Undetermined,1,/tmp/Undetermined_S0_L001_R1_001.fastq.gz,/tmp/Undetermined_S0_L001_R2_001.fastq.gz",
                "",
            ]
        ),
        encoding="utf-8",
    )
    units = tmp_path / "generated.units.tsv"
    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "bclconvert_fastq_list_to_units.py"),
            "--fastq-list",
            str(fastq_list),
            "--sample-sheet-rows",
            str(rows_tsv),
            "--run-id",
            "20260514_LH01106_0009_B23TVLGLT4",
            "--units-out",
            str(units),
        ],
        check=True,
    )

    unit_rows = _read_tsv(units)
    assert [(row["SAMPLEID"], row["LANEID"]) for row in unit_rows] == [
        ("HG003-a", "1"),
        ("HG003-a", "2"),
    ]
    assert unit_rows[0]["BARCODEID"] == "GAGTAATATACCGACCGTGA"


def test_bclconvert_lane_samplesheet_injects_zero_barcode_mismatches(tmp_path: Path) -> None:
    sample_sheet = tmp_path / "SampleSheet.csv"
    sample_sheet.write_text(
        "\n".join(
            [
                "[Header],",
                "FileFormatVersion,2",
                "RunName,run",
                "",
                "[Reads]",
                "Read1Cycles,151",
                "Index1Cycles,10",
                "Index2Cycles,10",
                "Read2Cycles,151",
                "",
                "[BCLConvert_Settings]",
                "SoftwareVersion,4.0.3",
                "",
                "[BCLConvert_Data]",
                "Sample_ID,Index,Index2",
                "HG003,GAGTAATATA,CCGACCGTGA",
                "",
            ]
        ),
        encoding="utf-8",
    )
    out = tmp_path / "L001" / "SampleSheet.csv"

    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "prepare_bclconvert_lane_samplesheet.py"),
            "--sample-sheet",
            str(sample_sheet),
            "--out",
            str(out),
            "--lane",
            "L001",
            "--settings-json",
            '{"BarcodeMismatchesIndex1": 0, "BarcodeMismatchesIndex2": 0}',
        ],
        check=True,
    )

    text = out.read_text(encoding="utf-8")
    assert "BarcodeMismatchesIndex1,0" in text
    assert "BarcodeMismatchesIndex2,0" in text


def test_bclconvert_lane_samplesheet_strips_fastqc_metrics_setting(tmp_path: Path) -> None:
    sample_sheet = tmp_path / "SampleSheet.csv"
    sample_sheet.write_text(
        "\n".join(
            [
                "[Header],",
                "FileFormatVersion,2",
                "RunName,run",
                "",
                "[Reads]",
                "Read1Cycles,151",
                "Index1Cycles,10",
                "Index2Cycles,10",
                "Read2Cycles,151",
                "",
                "[BCLConvert_Settings]",
                "SoftwareVersion,4.0.3",
                "GenerateFastqcMetrics,true",
                "",
                "[BCLConvert_Data]",
                "Sample_ID,Index,Index2",
                "HG003,GAGTAATATA,CCGACCGTGA",
                "",
            ]
        ),
        encoding="utf-8",
    )
    out = tmp_path / "L001" / "SampleSheet.csv"

    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "prepare_bclconvert_lane_samplesheet.py"),
            "--sample-sheet",
            str(sample_sheet),
            "--out",
            str(out),
            "--lane",
            "L001",
        ],
        check=True,
    )

    text = out.read_text(encoding="utf-8")
    assert "GenerateFastqcMetrics" not in text
    assert "SoftwareVersion,4.0.3" in text


def test_bclconvert_lane_samplesheet_rejects_invalid_barcode_mismatch(tmp_path: Path) -> None:
    sample_sheet = tmp_path / "SampleSheet.csv"
    sample_sheet.write_text(
        "\n".join(
            [
                "[Header],",
                "FileFormatVersion,2",
                "",
                "[Reads]",
                "Read1Cycles,151",
                "",
                "[BCLConvert_Settings]",
                "SoftwareVersion,4.0.3",
                "",
                "[BCLConvert_Data]",
                "Sample_ID,Index",
                "HG003,GAGTAATATA",
                "",
            ]
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "prepare_bclconvert_lane_samplesheet.py"),
            "--sample-sheet",
            str(sample_sheet),
            "--out",
            str(tmp_path / "out.csv"),
            "--lane",
            "1",
            "--settings-json",
            '{"BarcodeMismatchesIndex1": 3}',
        ],
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    assert "BarcodeMismatchesIndex1 must be 0, 1, or 2" in result.stderr


def test_bclconvert_metrics_to_multiqc_outputs_sample_first(tmp_path: Path) -> None:
    report_dir = tmp_path / "run_a" / "fastq" / "Reports"
    report_dir.mkdir(parents=True)
    for name in (
        "Demultiplex_Stats.csv",
        "fastq_list.csv",
        "Top_Unknown_Barcodes.csv",
        "Index_Hopping_Counts.csv",
    ):
        shutil.copy2(FIXTURE_DIR / name, report_dir / name)

    metrics_dir = tmp_path / "metrics"
    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "bclconvert_metrics_summary.py"),
            "--report-dir",
            str(report_dir),
            "--demux-out",
            str(metrics_dir / "demultiplex_stats.tsv"),
            "--unknown-out",
            str(metrics_dir / "unknown_barcodes.tsv"),
            "--hopping-out",
            str(metrics_dir / "index_hopping.tsv"),
            "--fastq-manifest-out",
            str(metrics_dir / "fastq_manifest.tsv"),
            "--rollup-json-out",
            str(metrics_dir / "rollup.json"),
        ],
        check=True,
    )

    mqc_dir = tmp_path / "other_reports"
    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "bclconvert_metrics_to_multiqc.py"),
            "--demux-tsv",
            str(metrics_dir / "demultiplex_stats.tsv"),
            "--unknown-tsv",
            str(metrics_dir / "unknown_barcodes.tsv"),
            "--hopping-tsv",
            str(metrics_dir / "index_hopping.tsv"),
            "--fastq-manifest-tsv",
            str(metrics_dir / "fastq_manifest.tsv"),
            "--rollup-json",
            str(metrics_dir / "rollup.json"),
            "--demux-out",
            str(mqc_dir / "bclconvert_demux_mqc.tsv"),
            "--unknown-out",
            str(mqc_dir / "bclconvert_unknown_barcodes_mqc.tsv"),
            "--hopping-out",
            str(mqc_dir / "bclconvert_index_hopping_mqc.tsv"),
            "--fastq-manifest-out",
            str(mqc_dir / "bclconvert_fastq_manifest_mqc.tsv"),
            "--lane-summary-out",
            str(mqc_dir / "bclconvert_lane_summary_mqc.tsv"),
        ],
        check=True,
    )

    demux_rows = _read_tsv(mqc_dir / "bclconvert_demux_mqc.tsv")
    assert demux_rows[0]["Sample"] == "run_a.L1.Omega_XTR_1-2-200_180.R1"
    assert demux_rows[0]["sample_id"] == "Omega_XTR_1-2-200_180"
    assert demux_rows[0]["reads"] == "1000"

    fastq_rows = _read_tsv(mqc_dir / "bclconvert_fastq_manifest_mqc.tsv")
    assert fastq_rows[0]["Sample"] == "run_a.L1.Omega_XTR_1-2-200_180.RG001"
    assert fastq_rows[0]["read1_file"].endswith("_R1_001.fastq.gz")

    unknown_rows = _read_tsv(mqc_dir / "bclconvert_unknown_barcodes_mqc.tsv")
    assert unknown_rows[0]["Sample"] == "run_a.L1.unknown_barcode.AAAAAAAAAA.CCCCCCCCCC"
    assert unknown_rows[0]["reads"] == "12"

    lane_rows = _read_tsv(mqc_dir / "bclconvert_lane_summary_mqc.tsv")
    assert {row["Sample"] for row in lane_rows} == {"run_a.L1", "run_a.L2"}
    assert next(row for row in lane_rows if row["Sample"] == "run_a.L1")["total_pf_reads"] == "1050"

    hopping_header = (mqc_dir / "bclconvert_index_hopping_mqc.tsv").read_text(encoding="utf-8").splitlines()[0]
    assert hopping_header.startswith("Sample\t")


def test_bclconvert_metrics_summary_accepts_lane_report_dirs(tmp_path: Path) -> None:
    report_dirs = []
    for lane in ("L001", "L002"):
        report_dir = tmp_path / "run_a" / "bclconvert" / "lane_fastqs" / lane / "Reports"
        report_dir.mkdir(parents=True)
        shutil.copy2(FIXTURE_DIR / "Demultiplex_Stats.csv", report_dir / "Demultiplex_Stats.csv")
        shutil.copy2(FIXTURE_DIR / "fastq_list.csv", report_dir / "fastq_list.csv")
        report_dirs.append(report_dir)

    metrics_dir = tmp_path / "metrics"
    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "bclconvert_metrics_summary.py"),
            "--report-dir",
            *(str(report_dir) for report_dir in report_dirs),
            "--run-id",
            "run_a",
            "--demux-out",
            str(metrics_dir / "demultiplex_stats.tsv"),
            "--unknown-out",
            str(metrics_dir / "unknown_barcodes.tsv"),
            "--hopping-out",
            str(metrics_dir / "index_hopping.tsv"),
            "--fastq-manifest-out",
            str(metrics_dir / "fastq_manifest.tsv"),
            "--rollup-json-out",
            str(metrics_dir / "rollup.json"),
        ],
        check=True,
    )

    demux_rows = _read_tsv(metrics_dir / "demultiplex_stats.tsv")
    manifest_rows = _read_tsv(metrics_dir / "fastq_manifest.tsv")
    rollup = json.loads((metrics_dir / "rollup.json").read_text(encoding="utf-8"))

    assert len(demux_rows) == 6
    assert len(manifest_rows) == 6
    assert rollup["run_id"] == "run_a"
    assert rollup["report_dirs"] == [str(report_dir) for report_dir in report_dirs]
    assert rollup["demultiplex_stats"]["total_pf_reads_by_lane"]["1"] == 2100


def test_prepare_bclconvert_demux_fastqc_inputs_makes_collision_safe_names(tmp_path: Path) -> None:
    fastq_dir = tmp_path / "fastqs"
    fastq_dir.mkdir()
    for name in (
        "sample_L001_R1.fastq.gz",
        "sample_L001_R2.fastq.gz",
        "sample_L002_R1.fastq.gz",
        "sample_L002_R2.fastq.gz",
    ):
        (fastq_dir / name).write_text("", encoding="utf-8")

    fastq_list = tmp_path / "fastq_list.csv"
    fastq_list.write_text(
        "\n".join(
            [
                "RGID,RGSM,RGLB,Lane,Read1File,Read2File",
                f"RG001,HG003,HG003,1,{fastq_dir / 'sample_L001_R1.fastq.gz'},{fastq_dir / 'sample_L001_R2.fastq.gz'}",
                f"RG001,HG003,HG003,2,{fastq_dir / 'sample_L002_R1.fastq.gz'},{fastq_dir / 'sample_L002_R2.fastq.gz'}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    input_dir = tmp_path / "fastqc_inputs"
    manifest = tmp_path / "demux_fastqc_inputs.tsv"
    mqc = tmp_path / "bclconvert_demux_fastqc_manifest_mqc.tsv"

    subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "prepare_bclconvert_demux_fastqc_inputs.py"),
            "--fastq-list",
            str(fastq_list),
            "--run-id",
            "20260514_LH01106_0009_B23TVLGLT4",
            "--input-dir",
            str(input_dir),
            "--manifest-out",
            str(manifest),
            "--multiqc-out",
            str(mqc),
        ],
        check=True,
    )

    rows = _read_tsv(manifest)
    assert [row["Sample"] for row in rows] == [
        "20260514_LH01106_0009_B23TVLGLT4.L1.HG003.RG001.R1",
        "20260514_LH01106_0009_B23TVLGLT4.L1.HG003.RG001.R2",
        "20260514_LH01106_0009_B23TVLGLT4.L2.HG003.RG001.R1",
        "20260514_LH01106_0009_B23TVLGLT4.L2.HG003.RG001.R2",
    ]
    assert len({row["fastqc_input"] for row in rows}) == len(rows)
    assert len({row["Sample"] for row in rows}) == len(rows)
    for row in rows:
        assert Path(row["fastqc_input"]).is_symlink()
        assert Path(os.readlink(row["fastqc_input"])).exists()
    assert _read_tsv(mqc) == rows


def test_prepare_bclconvert_demux_fastqc_inputs_rejects_identifier_collision(tmp_path: Path) -> None:
    fastq_dir = tmp_path / "fastqs"
    fastq_dir.mkdir()
    for name in ("a_R1.fastq.gz", "a_R2.fastq.gz", "b_R1.fastq.gz", "b_R2.fastq.gz"):
        (fastq_dir / name).write_text("", encoding="utf-8")
    fastq_list = tmp_path / "fastq_list.csv"
    fastq_list.write_text(
        "\n".join(
            [
                "RGID,RGSM,RGLB,Lane,Read1File,Read2File",
                f"RG001,HG003,HG003,1,{fastq_dir / 'a_R1.fastq.gz'},{fastq_dir / 'a_R2.fastq.gz'}",
                f"RG001,HG003,HG003,1,{fastq_dir / 'b_R1.fastq.gz'},{fastq_dir / 'b_R2.fastq.gz'}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "workflow" / "scripts" / "prepare_bclconvert_demux_fastqc_inputs.py"),
            "--fastq-list",
            str(fastq_list),
            "--run-id",
            "run",
            "--input-dir",
            str(tmp_path / "inputs"),
            "--manifest-out",
            str(tmp_path / "manifest.tsv"),
            "--multiqc-out",
            str(tmp_path / "mqc.tsv"),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "FastQC sample identifier collision" in result.stderr
