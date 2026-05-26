#!/usr/bin/env python3
"""Build Illumina run-level metrics tables from a run folder root."""

from __future__ import annotations

import argparse
import csv
import html
import math
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd


BCL_REPORT_DIR = "Analysis/1/Data/BCLConvert/fastq/Reports"

REQUIRED_FIXED_ARTIFACTS = {
    "RunInfo.xml": "RunInfo.xml",
    "RunParameters.xml": "RunParameters.xml",
    "SampleSheet.csv": "SampleSheet.csv",
}

REQUIRED_BCL_REPORTS = {
    "fastq_list.csv": f"{BCL_REPORT_DIR}/fastq_list.csv",
    "Quality_Metrics.csv": f"{BCL_REPORT_DIR}/Quality_Metrics.csv",
}

OPTIONAL_BCL_REPORTS = {
    "Adapter_Metrics.csv": f"{BCL_REPORT_DIR}/Adapter_Metrics.csv",
    "Demultiplex_Stats.csv": f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
    "Index_Hopping_Counts.csv": f"{BCL_REPORT_DIR}/Index_Hopping_Counts.csv",
    "Top_Unknown_Barcodes.csv": f"{BCL_REPORT_DIR}/Top_Unknown_Barcodes.csv",
    "Stats.json": f"{BCL_REPORT_DIR}/Stats.json",
}

OPTIONAL_INTEROP_FILES = {
    "IndexMetricsOut.bin": "InterOp/IndexMetricsOut.bin",
}

STANDARD_INTEROP_FILES = {
    "CorrectedIntMetricsOut.bin": "InterOp/CorrectedIntMetricsOut.bin",
    "EmpiricalPhasingMetricsOut.bin": "InterOp/EmpiricalPhasingMetricsOut.bin",
    "ExtendedTileMetricsOut.bin": "InterOp/ExtendedTileMetricsOut.bin",
    "ExtractionMetricsOut.bin": "InterOp/ExtractionMetricsOut.bin",
    "ImageMetricsOut.bin": "InterOp/ImageMetricsOut.bin",
    "QMetricsOut.bin": "InterOp/QMetricsOut.bin",
    "SummaryRunMetricsOut.bin": "InterOp/SummaryRunMetricsOut.bin",
    "TileMetricsOut.bin": "InterOp/TileMetricsOut.bin",
}

QUALITY_REQUIRED_COLUMNS = [
    "Lane",
    "SampleID",
    "ReadNumber",
    "Yield",
    "YieldQ30",
]

FASTQ_LIST_OUTPUT = "bclconvert_fastq_list.tsv"
QUALITY_WITH_READS_OUTPUT = "bclconvert_quality_metrics_with_read_equivalents.tsv"
QUALITY_BY_SAMPLE_OUTPUT = "bclconvert_quality_metrics_by_sample_lane.tsv"
QUALITY_BY_ANALYZED_OUTPUT = "bclconvert_quality_metrics_by_analyzed_sample_lane.tsv"
QUALITY_UNDETERMINED_OUTPUT = "bclconvert_quality_metrics_undetermined_by_lane.tsv"
DEMUX_SUMMARY_OUTPUT = "bclconvert_demux_summary.tsv"
RUN_METADATA_OUTPUT = "run_metadata.tsv"
ARTIFACT_STATUS_OUTPUT = "artifact_status.tsv"
SOURCE_OBJECTS_OUTPUT = "source_objects.tsv"
INTEROP_SUMMARY_OUTPUT = "interop_summary_metrics.tsv"


@dataclass(frozen=True)
class Artifact:
    artifact: str
    relative_path: str
    required: bool
    category: str


@dataclass
class SourceContext:
    run_dir: str
    is_s3: bool
    output_dir: Path
    tables_dir: Path
    local_subset: Path
    bucket: str = ""
    prefix: str = ""
    local_root: Path | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--mqc-out", required=True, type=Path)
    parser.add_argument("--aws-profile", default="")
    parser.add_argument("--aws-region", default="")
    return parser.parse_args()


def fail(message: str) -> None:
    raise SystemExit(message)


def parse_s3_uri(uri: str) -> tuple[str, str]:
    match = re.fullmatch(r"s3://([^/]+)/(.+?)/?", uri.strip())
    if not match:
        fail(f"Invalid S3 URI: {uri}")
    return match.group(1), match.group(2).rstrip("/")


def make_context(args: argparse.Namespace) -> SourceContext:
    run_dir = str(args.run_dir or "").strip()
    if run_dir == "":
        fail("illumina_run_metrics.run_dir is required")

    output_dir = args.output_dir
    tables_dir = output_dir / "raw_metric_tables"
    local_subset = output_dir / "source_run_subset"
    output_dir.mkdir(parents=True, exist_ok=True)
    tables_dir.mkdir(parents=True, exist_ok=True)
    local_subset.mkdir(parents=True, exist_ok=True)

    if run_dir.startswith("s3://"):
        if str(args.aws_profile or "").strip() == "":
            fail("illumina_run_metrics.aws_profile is required when run_dir starts with s3://")
        if str(args.aws_region or "").strip() == "":
            fail("illumina_run_metrics.aws_region is required when run_dir starts with s3://")
        bucket, prefix = parse_s3_uri(run_dir)
        return SourceContext(
            run_dir=run_dir.rstrip("/"),
            is_s3=True,
            output_dir=output_dir,
            tables_dir=tables_dir,
            local_subset=local_subset,
            bucket=bucket,
            prefix=prefix,
        )

    root = Path(run_dir).expanduser()
    if not root.exists():
        fail(f"Illumina run directory does not exist: {root}")
    if not root.is_dir():
        fail(f"Illumina run directory is not a directory: {root}")
    return SourceContext(
        run_dir=str(root),
        is_s3=False,
        output_dir=output_dir,
        tables_dir=tables_dir,
        local_subset=local_subset,
        local_root=root,
    )


def source_path(ctx: SourceContext, rel: str) -> str:
    if ctx.is_s3:
        return f"s3://{ctx.bucket}/{ctx.prefix}/{rel}"
    assert ctx.local_root is not None
    return str(ctx.local_root / rel)


def local_subset_path(ctx: SourceContext, rel: str) -> Path:
    return ctx.local_subset / rel


def safe_rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def classify_relpath(rel: str) -> str:
    if rel.startswith("InterOp/"):
        return "interop"
    if rel in {"RunInfo.xml", "RunParameters.xml", "SampleSheet.csv"}:
        return "run_metadata"
    if "/BCLConvert/" in rel and rel.endswith(".csv"):
        return "bclconvert_report"
    if "/BCLConvert/" in rel and rel.endswith(".json"):
        return "bclconvert_report"
    return "other"


def read_s3_inventory(ctx: SourceContext, profile: str, region: str) -> pd.DataFrame:
    try:
        import boto3
    except ImportError as exc:
        fail(f"boto3 is required for S3 run_dir access: {exc}")

    session = boto3.Session(profile_name=profile, region_name=region)
    client = session.client("s3")
    rows: list[dict[str, Any]] = []
    paginator = client.get_paginator("list_objects_v2")
    prefix = ctx.prefix.rstrip("/") + "/"
    for page in paginator.paginate(Bucket=ctx.bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = str(item["Key"])
            rel = key.removeprefix(prefix)
            if rel == key or rel == "":
                continue
            rows.append(
                {
                    "category": classify_relpath(rel),
                    "relative_path": rel,
                    "source_uri": f"s3://{ctx.bucket}/{key}",
                    "size_bytes": int(item.get("Size", 0)),
                    "last_modified": item.get("LastModified", "").isoformat()
                    if item.get("LastModified") is not None
                    else "",
                }
            )
    if not rows:
        fail(f"No S3 objects found under {ctx.run_dir}/")
    frame = pd.DataFrame(rows).sort_values(["category", "relative_path"])
    frame.to_csv(ctx.tables_dir / SOURCE_OBJECTS_OUTPUT, sep="\t", index=False)
    return frame


def read_local_inventory(ctx: SourceContext) -> pd.DataFrame:
    assert ctx.local_root is not None
    rows: list[dict[str, Any]] = []
    candidate_paths = set()
    for rel in (
        list(REQUIRED_FIXED_ARTIFACTS.values())
        + list(REQUIRED_BCL_REPORTS.values())
        + list(OPTIONAL_BCL_REPORTS.values())
        + list(OPTIONAL_INTEROP_FILES.values())
        + list(STANDARD_INTEROP_FILES.values())
    ):
        path = ctx.local_root / rel
        if path.exists():
            candidate_paths.add(path)

    for pattern in [
        "Analysis/*/Data/BCLConvert/**/Reports/*.csv",
        "Analysis/*/Data/BCLConvert/**/Reports/*.json",
        "**/BCLConvert/**/Reports/*.csv",
        "**/BCLConvert/**/Reports/*.json",
        "InterOp/*MetricsOut.bin",
    ]:
        candidate_paths.update(ctx.local_root.glob(pattern))

    for path in sorted(candidate_paths):
        if not path.is_file():
            continue
        stat = path.stat()
        rel = safe_rel(path, ctx.local_root)
        rows.append(
            {
                "category": classify_relpath(rel),
                "relative_path": rel,
                "source_uri": str(path),
                "size_bytes": int(stat.st_size),
                "last_modified": "",
            }
        )

    frame = pd.DataFrame(
        rows,
        columns=["category", "relative_path", "source_uri", "size_bytes", "last_modified"],
    )
    if not frame.empty:
        frame = frame.sort_values(["category", "relative_path"])
    frame.to_csv(ctx.tables_dir / SOURCE_OBJECTS_OUTPUT, sep="\t", index=False)
    return frame


def discover_report_relpaths(inventory: pd.DataFrame) -> dict[str, str]:
    available = set(inventory["relative_path"].astype(str)) if not inventory.empty else set()
    discovered: dict[str, str] = {}

    for name, canonical in {**REQUIRED_BCL_REPORTS, **OPTIONAL_BCL_REPORTS}.items():
        if canonical in available:
            discovered[name] = canonical
            continue
        matches = sorted(
            rel
            for rel in available
            if rel.endswith("/" + name)
            and "/BCLConvert/" in rel
            and "/Reports/" in rel
        )
        if len(matches) > 1:
            fail(
                "Multiple BCLConvert report candidates found for "
                f"{name}: {', '.join(matches)}"
            )
        if matches:
            discovered[name] = matches[0]

    return discovered


def artifact_plan(inventory: pd.DataFrame) -> list[Artifact]:
    discovered_reports = discover_report_relpaths(inventory)
    artifacts: list[Artifact] = []

    for name, rel in REQUIRED_FIXED_ARTIFACTS.items():
        artifacts.append(Artifact(name, rel, True, "run_metadata"))
    for name, default_rel in REQUIRED_BCL_REPORTS.items():
        artifacts.append(
            Artifact(name, discovered_reports.get(name, default_rel), True, "bclconvert_report")
        )
    for name, default_rel in OPTIONAL_BCL_REPORTS.items():
        artifacts.append(
            Artifact(name, discovered_reports.get(name, default_rel), False, "bclconvert_report")
        )
    for name, rel in OPTIONAL_INTEROP_FILES.items():
        artifacts.append(Artifact(name, rel, False, "interop"))
    for name, rel in STANDARD_INTEROP_FILES.items():
        artifacts.append(Artifact(name, rel, False, "interop"))

    return artifacts


def copy_local_artifact(ctx: SourceContext, rel: str) -> bool:
    assert ctx.local_root is not None
    src = ctx.local_root / rel
    if not src.exists():
        return False
    dest = local_subset_path(ctx, rel)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if src.resolve() != dest.resolve():
        shutil.copyfile(src, dest)
    return True


def download_s3_artifact(ctx: SourceContext, rel: str, profile: str, region: str) -> bool:
    try:
        import boto3
    except ImportError as exc:
        fail(f"boto3 is required for S3 run_dir access: {exc}")

    session = boto3.Session(profile_name=profile, region_name=region)
    client = session.client("s3")
    dest = local_subset_path(ctx, rel)
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        client.download_file(ctx.bucket, f"{ctx.prefix}/{rel}", str(dest))
    except Exception as exc:  # noqa: BLE001 - boto3 raises service-specific exceptions
        fail(f"Failed to download required S3 object {source_path(ctx, rel)}: {exc}")
    return True


def materialize_artifacts(
    ctx: SourceContext, inventory: pd.DataFrame, profile: str, region: str
) -> pd.DataFrame:
    available = set(inventory["relative_path"].astype(str)) if not inventory.empty else set()
    rows: list[dict[str, Any]] = []
    missing_required: list[str] = []

    for artifact in artifact_plan(inventory):
        present = artifact.relative_path in available
        local_path = local_subset_path(ctx, artifact.relative_path)
        status = "found" if present else "missing"

        if present:
            if ctx.is_s3:
                download_s3_artifact(ctx, artifact.relative_path, profile, region)
            else:
                copy_local_artifact(ctx, artifact.relative_path)

        if artifact.required and not present:
            missing_required.append(source_path(ctx, artifact.relative_path))

        rows.append(
            {
                "artifact": artifact.artifact,
                "category": artifact.category,
                "required": "yes" if artifact.required else "no",
                "status": status,
                "relative_path": artifact.relative_path,
                "source_path": source_path(ctx, artifact.relative_path),
                "local_path": str(local_path) if present else "",
            }
        )

    status_frame = pd.DataFrame(rows).sort_values(["required", "category", "artifact"])
    status_frame.to_csv(ctx.tables_dir / ARTIFACT_STATUS_OUTPUT, sep="\t", index=False)

    if missing_required:
        fail("Missing required Illumina run artifacts:\n" + "\n".join(missing_required))

    return status_frame


def xml_text(root: ET.Element, tag: str) -> str:
    elem = root.find(f".//{tag}")
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


def read_xml(path: Path) -> ET.Element:
    if not path.exists():
        fail(f"Missing required XML: {path}")
    return ET.parse(path).getroot()


def run_metadata(ctx: SourceContext) -> tuple[dict[str, str], list[dict[str, Any]]]:
    run_info_path = ctx.local_subset / "RunInfo.xml"
    run_parameters_path = ctx.local_subset / "RunParameters.xml"
    run_info = read_xml(run_info_path)
    run_parameters = read_xml(run_parameters_path)
    run_node = run_info.find(".//Run")
    reads = run_info.findall(".//Read")
    layout = run_info.find(".//FlowcellLayout")

    read_rows: list[dict[str, Any]] = []
    read_structure: list[str] = []
    for read in reads:
        number = read.attrib.get("Number", "")
        cycles = read.attrib.get("NumCycles", "")
        indexed = read.attrib.get("IsIndexedRead", "")
        read_structure.append(f"{number}:{cycles}:{indexed}")
        read_rows.append(
            {
                "read_number": number,
                "num_cycles": cycles,
                "is_indexed_read": indexed,
            }
        )

    meta = {
        "run_dir": ctx.run_dir,
        "run_id": "" if run_node is None else run_node.attrib.get("Id", ""),
        "run_number": "" if run_node is None else run_node.attrib.get("Number", ""),
        "experiment_name": xml_text(run_parameters, "ExperimentName"),
        "instrument": xml_text(run_info, "Instrument"),
        "flowcell": xml_text(run_info, "Flowcell"),
        "instrument_type": xml_text(run_parameters, "InstrumentType"),
        "flowcell_type": xml_text(run_parameters, "FlowCellType"),
        "application": xml_text(run_parameters, "Application"),
        "system_suite_version": xml_text(run_parameters, "SystemSuiteVersion"),
        "secondary_analysis_mode": xml_text(run_parameters, "SecondaryAnalysisMode"),
        "read_structure": ";".join(read_structure),
        "lane_count": "" if layout is None else layout.attrib.get("LaneCount", ""),
        "surface_count": "" if layout is None else layout.attrib.get("SurfaceCount", ""),
        "swath_count": "" if layout is None else layout.attrib.get("SwathCount", ""),
        "tile_count": "" if layout is None else layout.attrib.get("TileCount", ""),
    }
    pd.DataFrame(meta.items(), columns=["field", "value"]).to_csv(
        ctx.tables_dir / RUN_METADATA_OUTPUT, sep="\t", index=False
    )
    pd.DataFrame(read_rows).to_csv(
        ctx.tables_dir / "runinfo_reads.tsv", sep="\t", index=False
    )
    return meta, read_rows


def read_cycle_map(ctx: SourceContext) -> dict[int, int]:
    run_info = read_xml(ctx.local_subset / "RunInfo.xml")
    non_index_reads: list[tuple[int, int]] = []
    for read in run_info.findall(".//Read"):
        if read.attrib.get("IsIndexedRead") != "N":
            continue
        non_index_reads.append(
            (int(read.attrib["Number"]), int(read.attrib["NumCycles"]))
        )
    if not non_index_reads:
        fail("RunInfo.xml does not contain non-index reads.")

    cycles_by_read = {number: cycles for number, cycles in non_index_reads}
    for ordinal, (_number, cycles) in enumerate(non_index_reads, start=1):
        cycles_by_read.setdefault(ordinal, cycles)
    return cycles_by_read


def canonicalize_columns(frame: pd.DataFrame, required: list[str], source: Path) -> pd.DataFrame:
    lower_to_col = {str(col).strip().lower(): col for col in frame.columns}
    renamed = {}
    for required_col in required:
        key = required_col.lower()
        if key not in lower_to_col:
            continue
        renamed[lower_to_col[key]] = required_col
    frame = frame.rename(columns=renamed)
    missing = [col for col in required if col not in frame.columns]
    if missing:
        fail(f"{source} is missing required columns: {', '.join(missing)}")
    return frame


def artifact_rel(status: pd.DataFrame, artifact: str) -> str:
    rows = status[status["artifact"].astype(str) == artifact]
    if rows.empty:
        fail(f"Internal error: artifact status missing {artifact}")
    return str(rows.iloc[0]["relative_path"])


def read_table(ctx: SourceContext, status: pd.DataFrame, artifact: str) -> pd.DataFrame:
    rel = artifact_rel(status, artifact)
    path = ctx.local_subset / rel
    if not path.exists():
        fail(f"Missing required table after artifact materialization: {path}")
    return pd.read_csv(path)


def read_equivalent_tables(
    ctx: SourceContext, status: pd.DataFrame
) -> dict[str, float | int | str]:
    fastq = read_table(ctx, status, "fastq_list.csv")
    quality = read_table(ctx, status, "Quality_Metrics.csv")
    quality = canonicalize_columns(
        quality, QUALITY_REQUIRED_COLUMNS, ctx.local_subset / artifact_rel(status, "Quality_Metrics.csv")
    ).copy()

    if "index" not in quality.columns:
        quality["index"] = "na"
    if "index2" not in quality.columns:
        quality["index2"] = "na"

    cycles = read_cycle_map(ctx)
    for col in ["Lane", "ReadNumber", "Yield", "YieldQ30"]:
        quality[col] = pd.to_numeric(quality[col], errors="coerce")
    if quality[["Lane", "ReadNumber", "Yield", "YieldQ30"]].isna().any().any():
        fail(
            "Quality_Metrics.csv contains non-numeric Lane, ReadNumber, Yield, or YieldQ30 values."
        )

    quality["read_cycles"] = quality["ReadNumber"].astype(int).map(cycles)
    if quality["read_cycles"].isna().any():
        missing_reads = sorted(
            quality.loc[quality["read_cycles"].isna(), "ReadNumber"].astype(int).unique()
        )
        fail(
            "BCLConvert ReadNumber values are not represented in RunInfo.xml "
            f"non-index reads: {missing_reads}"
        )

    quality["read_equivalents"] = quality["Yield"] / quality["read_cycles"]
    quality["q30_read_equivalent_bases"] = quality["YieldQ30"]
    quality["SampleID"] = quality["SampleID"].astype(str)
    quality["Lane"] = quality["Lane"].astype(int)
    quality["ReadNumber"] = quality["ReadNumber"].astype(int)
    quality["index"] = quality["index"].fillna("na").astype(str)
    quality["index2"] = quality["index2"].fillna("na").astype(str)

    quality.to_csv(ctx.tables_dir / QUALITY_WITH_READS_OUTPUT, sep="\t", index=False)
    fastq.to_csv(ctx.tables_dir / FASTQ_LIST_OUTPUT, sep="\t", index=False)

    grouped = (
        quality.groupby(["SampleID", "Lane", "index", "index2"], dropna=False)
        .agg(
            yield_bases=("Yield", "sum"),
            yield_q30_bases=("YieldQ30", "sum"),
            read_equivalents=("read_equivalents", "sum"),
            read_count_rows=("ReadNumber", "count"),
        )
        .reset_index()
    )
    grouped["sample_lane_id"] = (
        grouped["SampleID"].astype(str)
        + "_L"
        + grouped["Lane"].astype(int).astype(str).str.zfill(3)
    )
    grouped.to_csv(ctx.tables_dir / QUALITY_BY_SAMPLE_OUTPUT, sep="\t", index=False)

    analyzed = grouped[grouped["SampleID"].astype(str) != "Undetermined"].copy()
    undetermined = grouped[grouped["SampleID"].astype(str) == "Undetermined"].copy()
    analyzed.to_csv(ctx.tables_dir / QUALITY_BY_ANALYZED_OUTPUT, sep="\t", index=False)
    undetermined.to_csv(ctx.tables_dir / QUALITY_UNDETERMINED_OUTPUT, sep="\t", index=False)

    summary = {
        "fastq_list_rows": int(len(fastq)),
        "fastq_list_unique_rgsm": int(fastq["RGSM"].nunique()) if "RGSM" in fastq.columns else 0,
        "quality_metric_rows": int(len(quality)),
        "quality_metric_unique_samples": int(quality["SampleID"].nunique()),
        "quality_metric_sample_lanes": int(
            quality[["SampleID", "Lane"]].drop_duplicates().shape[0]
        ),
        "analyzed_unique_samples": int(analyzed["SampleID"].nunique()),
        "analyzed_sample_lanes": int(analyzed[["SampleID", "Lane"]].drop_duplicates().shape[0]),
        "undetermined_lanes": int(undetermined["Lane"].nunique()),
        "analyzed_yield_bases": float(analyzed["yield_bases"].sum()),
        "analyzed_yield_q30_bases": float(analyzed["yield_q30_bases"].sum()),
        "analyzed_read_equivalents": float(analyzed["read_equivalents"].sum()),
        "undetermined_yield_bases": float(undetermined["yield_bases"].sum()),
        "undetermined_yield_q30_bases": float(undetermined["yield_q30_bases"].sum()),
        "undetermined_read_equivalents": float(undetermined["read_equivalents"].sum()),
        "total_yield_bases": float(grouped["yield_bases"].sum()),
        "total_yield_q30_bases": float(grouped["yield_q30_bases"].sum()),
        "total_read_equivalents": float(grouped["read_equivalents"].sum()),
    }
    pd.DataFrame(summary.items(), columns=["field", "value"]).to_csv(
        ctx.tables_dir / DEMUX_SUMMARY_OUTPUT, sep="\t", index=False
    )
    return summary


def decode_object_columns(frame: pd.DataFrame) -> pd.DataFrame:
    result = frame.copy()
    for col in result.columns:
        if result[col].dtype == object:
            result[col] = result[col].map(lambda value: value.decode() if isinstance(value, bytes) else value)
    return result


def parse_interop_tables(ctx: SourceContext, status: pd.DataFrame) -> dict[str, float | str]:
    interop_rows = status[
        (status["category"].astype(str) == "interop")
        & (status["status"].astype(str) == "found")
        & (status["artifact"].astype(str).isin(STANDARD_INTEROP_FILES))
    ]
    if interop_rows.empty:
        summary = {
            "interop_available": "no",
            "raw_single_read_observations": math.nan,
            "pf_single_read_observations": math.nan,
            "raw_non_index_read_observations": math.nan,
            "pf_non_index_read_observations": math.nan,
            "non_pf_non_index_read_observations": math.nan,
            "interop_percent_q30": math.nan,
            "interop_yield_g": math.nan,
        }
        pd.DataFrame(summary.items(), columns=["field", "value"]).to_csv(
            ctx.tables_dir / INTEROP_SUMMARY_OUTPUT, sep="\t", index=False
        )
        return summary

    try:
        from interop import core as interop_core
    except ImportError as exc:
        fail(f"InterOp files were found but the interop Python package is unavailable: {exc}")

    tables: dict[str, pd.DataFrame] = {}
    for level in ["Total", "Read", "Lane", "Surface"]:
        try:
            frame = pd.DataFrame.from_records(
                interop_core.summary(str(ctx.local_subset), level=level)
            )
        except Exception as exc:  # noqa: BLE001 - interop raises wrapped C++ exceptions
            fail(f"Failed to parse InterOp summary level {level} from {ctx.local_subset}: {exc}")
        frame = decode_object_columns(frame)
        out = ctx.tables_dir / f"interop_summary_{level.lower()}.tsv"
        frame.to_csv(out, sep="\t", index=False)
        tables[level.lower()] = frame

    total = tables["total"]
    if total.empty:
        fail(f"InterOp summary total table is empty for {ctx.local_subset}")
    row = total.iloc[0]
    raw_single = float(row.get("Reads", row.get("Cluster Count", 0)) or 0)
    pf_single = float(row.get("Reads Pf", row.get("Cluster Count Pf", 0)) or 0)
    non_index_count = len(
        [
            r
            for r in read_xml(ctx.local_subset / "RunInfo.xml").findall(".//Read")
            if r.attrib.get("IsIndexedRead") == "N"
        ]
    )
    summary = {
        "interop_available": "yes",
        "raw_single_read_observations": raw_single,
        "pf_single_read_observations": pf_single,
        "raw_non_index_read_observations": raw_single * non_index_count,
        "pf_non_index_read_observations": pf_single * non_index_count,
        "non_pf_non_index_read_observations": (raw_single - pf_single) * non_index_count,
        "interop_percent_q30": float(row.get("% >= Q30", 0) or 0),
        "interop_yield_g": float(row.get("Yield G", 0) or 0),
    }
    pd.DataFrame(summary.items(), columns=["field", "value"]).to_csv(
        ctx.tables_dir / INTEROP_SUMMARY_OUTPUT, sep="\t", index=False
    )
    return summary


def fmt(value: Any) -> str:
    if value in [None, ""]:
        return ""
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    if not math.isfinite(number):
        return "NA"
    if abs(number) >= 1000:
        return f"{number:,.0f}"
    if abs(number) >= 1:
        return f"{number:.3f}".rstrip("0").rstrip(".")
    return f"{number:.6g}"


def markdown_table(frame: pd.DataFrame, columns: list[str], limit: int | None = None) -> str:
    if frame.empty:
        return "_None._"
    shown = frame[columns].head(limit) if limit else frame[columns]
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join(["---"] * len(columns)) + " |",
    ]
    for _, row in shown.iterrows():
        lines.append("| " + " | ".join(str(row[col]) for col in columns) + " |")
    if limit and len(frame) > limit:
        lines.append(f"| ... | {len(frame) - limit} additional rows omitted | | | | |")
    return "\n".join(lines)


def write_mqc(
    ctx: SourceContext,
    mqc_out: Path,
    run_meta: dict[str, str],
    status: pd.DataFrame,
    demux: dict[str, float | int | str],
    interop: dict[str, float | str],
) -> None:
    sample = run_meta.get("run_id") or Path(ctx.run_dir.rstrip("/")).name or "illumina_run"
    rows = [
        {"sample": sample, "metric": "bclconvert_analyzed_read_equivalents", "value": demux["analyzed_read_equivalents"]},
        {"sample": sample, "metric": "bclconvert_undetermined_read_equivalents", "value": demux["undetermined_read_equivalents"]},
        {"sample": sample, "metric": "bclconvert_total_read_equivalents", "value": demux["total_read_equivalents"]},
        {"sample": sample, "metric": "bclconvert_analyzed_sample_lanes", "value": demux["analyzed_sample_lanes"]},
        {"sample": sample, "metric": "bclconvert_undetermined_lanes", "value": demux["undetermined_lanes"]},
        {"sample": sample, "metric": "interop_pf_non_index_read_observations", "value": interop["pf_non_index_read_observations"]},
        {"sample": sample, "metric": "interop_percent_q30", "value": interop["interop_percent_q30"]},
        {
            "sample": sample,
            "metric": "missing_required_artifacts",
            "value": int(((status["required"] == "yes") & (status["status"] == "missing")).sum()),
        },
        {
            "sample": sample,
            "metric": "missing_optional_artifacts",
            "value": int(((status["required"] == "no") & (status["status"] == "missing")).sum()),
        },
    ]
    mqc_out.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(mqc_out, sep="\t", index=False)


def write_report(
    ctx: SourceContext,
    run_meta: dict[str, str],
    status: pd.DataFrame,
    demux: dict[str, float | int | str],
    interop: dict[str, float | str],
) -> None:
    found = status[status["status"] == "found"].copy()
    missing = status[status["status"] == "missing"].copy()
    required_missing = missing[missing["required"] == "yes"]
    optional_missing = missing[missing["required"] == "no"]

    content = [
        "# Illumina Run Metrics",
        "",
        "## Run Identity",
        "",
        f"- Run directory: `{ctx.run_dir}`",
        f"- Run ID: `{run_meta.get('run_id', '')}`",
        f"- Instrument: `{run_meta.get('instrument', '')}`",
        f"- Flowcell: `{run_meta.get('flowcell', '')}`",
        f"- Flowcell type: `{run_meta.get('flowcell_type', '')}`",
        f"- Read structure: `{run_meta.get('read_structure', '')}`",
        "",
        "## Required Artifact Status",
        "",
        markdown_table(
            status[status["required"] == "yes"],
            ["artifact", "status", "relative_path", "source_path", "local_path"],
        ),
        "",
        "## Optional Missing Artifacts",
        "",
        markdown_table(
            optional_missing,
            ["artifact", "status", "relative_path", "source_path", "local_path"],
        ),
        "",
        "## BCLConvert Read Equivalents",
        "",
        f"- FASTQ list rows: {fmt(demux['fastq_list_rows'])}",
        f"- Analyzed samples: {fmt(demux['analyzed_unique_samples'])}",
        f"- Analyzed sample-lanes: {fmt(demux['analyzed_sample_lanes'])}",
        f"- Undetermined lanes: {fmt(demux['undetermined_lanes'])}",
        f"- Analyzed read equivalents: {fmt(demux['analyzed_read_equivalents'])}",
        f"- Undetermined read equivalents: {fmt(demux['undetermined_read_equivalents'])}",
        f"- Total read equivalents: {fmt(demux['total_read_equivalents'])}",
        "",
        "## InterOp Summary",
        "",
        f"- InterOp available: {interop['interop_available']}",
        f"- PF non-index read observations: {fmt(interop['pf_non_index_read_observations'])}",
        f"- Raw non-index read observations: {fmt(interop['raw_non_index_read_observations'])}",
        f"- InterOp percent Q30: {fmt(interop['interop_percent_q30'])}",
        "",
        "## Raw Tables",
        "",
        f"- `{ctx.tables_dir}`",
    ]
    if not required_missing.empty:
        content.extend(["", "## Required Missing Artifacts", "", markdown_table(required_missing, ["artifact", "source_path"])])
    if found.empty:
        content.extend(["", "## Found Artifacts", "", "_None._"])

    md = ctx.output_dir / "illumina_run_metrics.md"
    html_out = ctx.output_dir / "illumina_run_metrics.html"
    md.write_text("\n".join(content) + "\n", encoding="utf-8")
    html_body = html.escape("\n".join(content)).replace("\n", "<br>\n")
    html_out.write_text(
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>"
        "Illumina Run Metrics</title></head><body><pre>"
        + html_body
        + "</pre></body></html>\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    ctx = make_context(args)

    if ctx.is_s3:
        inventory = read_s3_inventory(ctx, str(args.aws_profile).strip(), str(args.aws_region).strip())
    else:
        inventory = read_local_inventory(ctx)

    status = materialize_artifacts(
        ctx,
        inventory,
        str(args.aws_profile).strip(),
        str(args.aws_region).strip(),
    )
    run_meta, _read_rows = run_metadata(ctx)
    demux = read_equivalent_tables(ctx, status)
    interop = parse_interop_tables(ctx, status)
    write_mqc(ctx, args.mqc_out, run_meta, status, demux, interop)
    write_report(ctx, run_meta, status, demux, interop)

    print(f"Wrote {ctx.output_dir / 'illumina_run_metrics.html'}")
    print(f"Wrote {ctx.output_dir / 'illumina_run_metrics.md'}")
    print(f"Wrote {ctx.tables_dir}")
    print(f"Wrote {args.mqc_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
