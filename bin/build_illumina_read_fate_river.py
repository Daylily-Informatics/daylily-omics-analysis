#!/usr/bin/env python3
"""Build an Illumina read-fate Sankey from InterOp, BCLConvert, and alignstats."""

from __future__ import annotations

import argparse
import math
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import pandas as pd


REPORT_PREFIX = "illumina_read_fate_river"
REPORT_TITLE = "Illumina Read-Fate River"

RUN_OBJECTS = [
    "RunInfo.xml",
    "RunParameters.xml",
    "SampleSheet.csv",
    "RunCompletionStatus.xml",
    "Analysis/1/Data/BCLConvert/SampleSheet.csv",
    "Analysis/1/Data/BCLConvert/fastq/Reports/fastq_list.csv",
    "Analysis/1/Data/BCLConvert/fastq/Reports/Quality_Metrics.csv",
    "Analysis/1/Data/BCLConvert/fastq/Reports/Adapter_Metrics.csv",
]

STANDARD_INTEROP_OBJECTS = [
    "InterOp/CorrectedIntMetricsOut.bin",
    "InterOp/EmpiricalPhasingMetricsOut.bin",
    "InterOp/ExtendedTileMetricsOut.bin",
    "InterOp/ExtractionMetricsOut.bin",
    "InterOp/ImageMetricsOut.bin",
    "InterOp/QMetricsOut.bin",
    "InterOp/SummaryRunMetricsOut.bin",
    "InterOp/TileMetricsOut.bin",
]

EXPECTED_MAYBE_MISSING = [
    "Analysis/1/Data/BCLConvert/fastq/Reports/Demultiplex_Stats.csv",
    "Analysis/1/Data/BCLConvert/fastq/Reports/Index_Hopping_Counts.csv",
    "Analysis/1/Data/BCLConvert/fastq/Reports/Top_Unknown_Barcodes.csv",
    "Analysis/1/Data/BCLConvert/fastq/Reports/Stats.json",
    "InterOp/IndexMetricsOut.bin",
    "pre_alignment_filter_metrics",
]

REQUIRED_ALIGNSTATS_COLUMNS = [
    "YieldReads",
    "YieldBases",
    "MappedReads",
    "UnmappedReads",
    "MappedBases",
    "UnmappedBases",
    "WgsAlignedReads",
    "WgsCalculatedAlignedReads",
    "WgsCovDuplicateReads",
    "WgsCoverageBases1",
    "WgsCoverageBases10",
    "WgsCoverageBases20",
    "WgsCoverageBases30",
    "WgsCoverageMean",
]


@dataclass
class S3Object:
    key: str
    size: int
    last_modified: str


@dataclass
class RunContext:
    bucket: str
    prefix: str
    run_s3_uri: str
    local_run: Path
    tables_dir: Path
    existing_tables_dir: Path | None
    commands: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build read-fate river outputs from Illumina raw metrics and "
            "Daylily alignstats combo TSV."
        )
    )
    parser.add_argument("--alignstats-combo", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--profile")
    parser.add_argument("--region")
    parser.add_argument("--run-s3-uri", required=True)
    parser.add_argument("--local-run-dir", type=Path)
    parser.add_argument("--report-prefix", default=REPORT_PREFIX)
    parser.add_argument("--report-title", default=REPORT_TITLE)
    parser.add_argument(
        "--skip-fetch",
        action="store_true",
        help="Use already-downloaded metrics under output-dir/source_run_subset or --local-run-dir.",
    )
    return parser.parse_args()


def require_columns(frame: pd.DataFrame, columns: list[str], source: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        joined = ", ".join(missing)
        raise SystemExit(f"{source} is missing required columns: {joined}")


def parse_s3_uri(uri: str) -> tuple[str, str]:
    match = re.fullmatch(r"s3://([^/]+)/(.+?)/?", uri.strip())
    if not match:
        raise SystemExit(f"Invalid S3 URI: {uri}")
    return match.group(1), match.group(2)


def xml_text(root: ET.Element, tag: str) -> str:
    elem = root.find(f".//{tag}")
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


def read_xml(path: Path) -> ET.Element:
    if not path.exists():
        raise SystemExit(f"Missing required XML: {path}")
    return ET.parse(path).getroot()


def s3_client(profile: str, region: str):
    if not profile:
        raise SystemExit("--profile is required when --skip-fetch is not used.")
    if profile == "default":
        raise SystemExit("AWS profile name 'default' is not allowed; pass an explicit profile.")
    if not region:
        raise SystemExit("--region is required when --skip-fetch is not used.")
    try:
        import boto3
    except ImportError as exc:
        raise SystemExit(
            "Python package 'boto3' is required when --skip-fetch is not used."
        ) from exc
    session = boto3.Session(profile_name=profile, region_name=region)
    return session.client("s3")


def iter_s3_objects(client, bucket: str, prefix: str) -> Iterable[S3Object]:
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix.rstrip("/") + "/"):
        for item in page.get("Contents", []):
            yield S3Object(
                key=item["Key"],
                size=int(item["Size"]),
                last_modified=item["LastModified"].isoformat(),
            )


def classify_object(rel: str) -> str:
    if rel.startswith("InterOp/"):
        return "interop"
    if "/fastq/Reports/" in rel or rel.endswith("SampleSheet.csv"):
        return "bclconvert_report"
    if rel in {"RunInfo.xml", "RunParameters.xml"}:
        return "run_metadata"
    if rel.endswith(".fastq.gz"):
        return "fastq"
    return "other"


def write_inventory(objects: list[S3Object], ctx: RunContext) -> pd.DataFrame:
    rows = []
    for obj in objects:
        rel = obj.key.removeprefix(ctx.prefix.rstrip("/") + "/")
        rows.append(
            {
                "category": classify_object(rel),
                "s3_uri": f"s3://{ctx.bucket}/{obj.key}",
                "size_bytes": obj.size,
                "last_modified": obj.last_modified,
            }
        )
    frame = pd.DataFrame(rows)
    frame.to_csv(ctx.tables_dir / "source_objects.tsv", sep="\t", index=False)
    return frame


def download_if_present(client, ctx: RunContext, available: set[str], rel: str) -> bool:
    if rel not in available:
        return False
    dest = ctx.local_run / rel
    if dest.exists() and dest.stat().st_size > 0:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    client.download_file(ctx.bucket, f"{ctx.prefix.rstrip('/')}/{rel}", str(dest))
    return True


def fetch_raw_metrics(
    ctx: RunContext, profile: str, region: str
) -> tuple[pd.DataFrame, list[str]]:
    client = s3_client(profile, region)
    ctx.commands.append(f"boto3 list_objects_v2 {ctx.run_s3_uri}/")
    objects = list(iter_s3_objects(client, ctx.bucket, ctx.prefix))
    if not objects:
        raise SystemExit(f"No S3 objects found under {ctx.run_s3_uri}/")
    inventory = write_inventory(objects, ctx)
    available = {obj.key.removeprefix(ctx.prefix.rstrip("/") + "/") for obj in objects}
    missing_downloads = []
    for rel in RUN_OBJECTS + STANDARD_INTEROP_OBJECTS:
        ctx.commands.append(f"boto3 download_file {ctx.run_s3_uri}/{rel}")
        if not download_if_present(client, ctx, available, rel):
            missing_downloads.append(rel)
    return inventory, missing_downloads


def existing_metrics_source(output_dir: Path, local_run_dir: Path | None) -> tuple[Path, Path | None]:
    if local_run_dir is not None:
        if not (local_run_dir / "RunInfo.xml").exists():
            raise SystemExit(f"--local-run-dir is missing RunInfo.xml: {local_run_dir}")
        tables_dir = local_run_dir.parent / "raw_metric_tables"
        return local_run_dir, tables_dir if tables_dir.exists() else None
    local_run = output_dir / "source_run_subset"
    tables_dir = output_dir / "raw_metric_tables"
    if (local_run / "RunInfo.xml").exists():
        return local_run, tables_dir if tables_dir.exists() else None
    raise SystemExit(
        "No downloaded metrics found. Run without --skip-fetch, provide --local-run-dir, "
        "or stage output-dir/source_run_subset."
    )


def copy_existing_inventory(ctx: RunContext) -> pd.DataFrame:
    if ctx.existing_tables_dir is None:
        return pd.DataFrame(
            columns=["category", "s3_uri", "size_bytes", "last_modified"]
        )
    source = ctx.existing_tables_dir / "source_objects.tsv"
    if not source.exists():
        return pd.DataFrame(
            columns=["category", "s3_uri", "size_bytes", "last_modified"]
        )
    dest = ctx.tables_dir / "source_objects.tsv"
    if source.resolve() != dest.resolve():
        shutil.copyfile(source, dest)
    return pd.read_csv(dest, sep="\t")


def parse_run_metadata(ctx: RunContext) -> dict[str, str]:
    run_info = read_xml(ctx.local_run / "RunInfo.xml")
    run_params = read_xml(ctx.local_run / "RunParameters.xml")
    run_node = run_info.find(".//Run")
    reads = run_info.findall(".//Read")
    layout = run_info.find(".//FlowcellLayout")
    read_structure = ";".join(
        f"{r.attrib.get('Number')}:{r.attrib.get('NumCycles')}:{r.attrib.get('IsIndexedRead')}"
        for r in reads
    )
    meta = {
        "run_s3_uri": ctx.run_s3_uri,
        "run_id": "" if run_node is None else run_node.attrib.get("Id", ""),
        "run_number": "" if run_node is None else run_node.attrib.get("Number", ""),
        "experiment_name": xml_text(run_params, "ExperimentName"),
        "instrument": xml_text(run_info, "Instrument"),
        "flowcell": xml_text(run_info, "Flowcell"),
        "instrument_type": xml_text(run_params, "InstrumentType"),
        "flowcell_type": xml_text(run_params, "FlowCellType"),
        "application": xml_text(run_params, "Application"),
        "system_suite_version": xml_text(run_params, "SystemSuiteVersion"),
        "secondary_analysis_mode": xml_text(run_params, "SecondaryAnalysisMode"),
        "read_structure": read_structure,
        "lane_count": "" if layout is None else layout.attrib.get("LaneCount", ""),
        "surface_count": ""
        if layout is None
        else layout.attrib.get("SurfaceCount", ""),
        "swath_count": "" if layout is None else layout.attrib.get("SwathCount", ""),
        "tile_count": "" if layout is None else layout.attrib.get("TileCount", ""),
    }
    pd.DataFrame(meta.items(), columns=["field", "value"]).to_csv(
        ctx.tables_dir / "run_metadata.tsv", sep="\t", index=False
    )
    return meta


def biological_read_cycles(ctx: RunContext) -> dict[int, int]:
    run_info = read_xml(ctx.local_run / "RunInfo.xml")
    non_index = [
        int(r.attrib["NumCycles"])
        for r in run_info.findall(".//Read")
        if r.attrib.get("IsIndexedRead") == "N"
    ]
    if not non_index:
        raise SystemExit("RunInfo.xml does not contain non-index read cycles.")
    return {idx + 1: cycles for idx, cycles in enumerate(non_index)}


def read_bcl_csv(
    ctx: RunContext, name: str, required: bool = True
) -> pd.DataFrame | None:
    path = ctx.local_run / "Analysis/1/Data/BCLConvert/fastq/Reports" / name
    if not path.exists():
        if required:
            raise SystemExit(f"Missing required BCLConvert report: {path}")
        return None
    return pd.read_csv(path)


def summarize_bclconvert(
    ctx: RunContext, inventory: pd.DataFrame
) -> dict[str, float | int | str]:
    fastq = read_bcl_csv(ctx, "fastq_list.csv")
    quality = read_bcl_csv(ctx, "Quality_Metrics.csv")
    assert fastq is not None
    assert quality is not None
    cycles_by_read = biological_read_cycles(ctx)

    quality = quality.copy()
    for col in ["Yield", "YieldQ30", "% Q30", "Mean Quality Score (PF)"]:
        quality[col] = pd.to_numeric(quality[col], errors="coerce")
    quality["read_cycles"] = quality["ReadNumber"].map(cycles_by_read)
    if quality["read_cycles"].isna().any():
        missing = sorted(
            quality.loc[quality["read_cycles"].isna(), "ReadNumber"].unique()
        )
        raise SystemExit(
            f"BCLConvert ReadNumber values missing RunInfo cycle mapping: {missing}"
        )
    quality["read_equivalents"] = quality["Yield"] / quality["read_cycles"]
    quality["read_equivalents"] = quality["read_equivalents"].round().astype("int64")
    quality["q30_read_equivalent_bases"] = quality["YieldQ30"]
    quality.to_csv(
        ctx.tables_dir / "bclconvert_quality_metrics_with_read_equivalents.tsv",
        sep="\t",
        index=False,
    )
    fastq.to_csv(ctx.tables_dir / "bclconvert_fastq_list.tsv", sep="\t", index=False)

    sample_lane = quality.copy()
    sample_lane["index"] = sample_lane["index"].fillna("na")
    sample_lane["index2"] = sample_lane["index2"].fillna("na")
    grouped = (
        sample_lane.groupby(["SampleID", "Lane", "index", "index2"], dropna=False)
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
        + grouped["Lane"].astype(str).str.zfill(3)
    )
    grouped.to_csv(
        ctx.tables_dir / "bclconvert_quality_metrics_by_sample_lane.tsv",
        sep="\t",
        index=False,
    )
    undetermined = grouped[grouped["SampleID"].astype(str) == "Undetermined"].copy()
    analyzed = grouped[grouped["SampleID"].astype(str) != "Undetermined"].copy()
    undetermined.to_csv(
        ctx.tables_dir / "bclconvert_quality_metrics_undetermined_by_lane.tsv",
        sep="\t",
        index=False,
    )
    analyzed.to_csv(
        ctx.tables_dir / "bclconvert_quality_metrics_by_analyzed_sample_lane.tsv",
        sep="\t",
        index=False,
    )

    undetermined_objects = pd.DataFrame()
    if not inventory.empty and "s3_uri" in inventory.columns:
        undetermined_objects = inventory[
            inventory["s3_uri"]
            .astype(str)
            .str.contains("/Undetermined_S0_L", regex=False)
        ].copy()
    undetermined_objects.to_csv(
        ctx.tables_dir / "undetermined_fastq_objects.tsv", sep="\t", index=False
    )

    demux_summary = {
        "fastq_list_rows": int(len(fastq)),
        "fastq_list_unique_rgsm": int(fastq["RGSM"].nunique())
        if "RGSM" in fastq.columns
        else 0,
        "fastq_list_lanes": ",".join(
            str(x) for x in sorted(fastq["Lane"].dropna().unique())
        ),
        "quality_metric_rows": int(len(quality)),
        "quality_metric_unique_samples": int(quality["SampleID"].nunique()),
        "quality_metric_sample_lanes": int(
            quality[["SampleID", "Lane"]].drop_duplicates().shape[0]
        ),
        "analyzed_unique_samples": int(analyzed["SampleID"].nunique()),
        "analyzed_sample_lanes": int(
            analyzed[["SampleID", "Lane"]].drop_duplicates().shape[0]
        ),
        "undetermined_lanes": int(undetermined["Lane"].nunique()),
        "analyzed_yield_bases": float(analyzed["yield_bases"].sum()),
        "analyzed_read_equivalents": float(analyzed["read_equivalents"].sum()),
        "undetermined_yield_bases": float(undetermined["yield_bases"].sum()),
        "undetermined_read_equivalents": float(undetermined["read_equivalents"].sum()),
        "total_yield_bases": float(grouped["yield_bases"].sum()),
        "total_read_equivalents": float(grouped["read_equivalents"].sum()),
        "undetermined_fastq_objects": int(len(undetermined_objects)),
    }
    pd.DataFrame(demux_summary.items(), columns=["field", "value"]).to_csv(
        ctx.tables_dir / "bclconvert_demux_summary.tsv", sep="\t", index=False
    )
    return demux_summary


def install_interop_if_needed(output_dir: Path) -> Path:
    try:
        import interop  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            "Python package 'interop' is required to parse Illumina InterOp metrics. "
            "Install it in the active execution environment before running this script."
        ) from exc
    return output_dir


def record_array_to_frame(arr) -> pd.DataFrame:
    frame = pd.DataFrame.from_records(arr)
    for col in frame.columns:
        if frame[col].dtype == object:
            frame[col] = frame[col].map(
                lambda x: x.decode() if isinstance(x, bytes) else x
            )
    return frame


def load_or_write_interop_tables(
    ctx: RunContext, output_dir: Path
) -> dict[str, pd.DataFrame]:
    tables: dict[str, pd.DataFrame] = {}
    existing = ctx.existing_tables_dir
    if existing is not None:
        all_exist = True
        for level in ["total", "read", "lane", "surface"]:
            src = existing / f"interop_summary_{level}.tsv"
            if not src.exists():
                all_exist = False
                break
        if all_exist:
            for level in ["total", "read", "lane", "surface"]:
                src = existing / f"interop_summary_{level}.tsv"
                dest = ctx.tables_dir / src.name
                if src.resolve() != dest.resolve():
                    shutil.copyfile(src, dest)
                tables[level] = pd.read_csv(dest, sep="\t")
            return tables

    deps = install_interop_if_needed(output_dir)
    sys.path.insert(0, str(deps))
    from interop import core as interop_core

    for level in ["Total", "Read", "Lane", "Surface"]:
        frame = record_array_to_frame(
            interop_core.summary(str(ctx.local_run), level=level)
        )
        out_path = ctx.tables_dir / f"interop_summary_{level.lower()}.tsv"
        frame.to_csv(out_path, sep="\t", index=False)
        tables[level.lower()] = frame
    return tables


def summarize_interop(
    tables: dict[str, pd.DataFrame], non_index_read_count: int
) -> dict[str, float]:
    total = tables.get("total")
    if total is None or total.empty:
        raise SystemExit("Missing InterOp total summary table.")
    row = total.iloc[0]
    raw_single_read = float(row.get("Reads", row.get("Cluster Count", 0)))
    pf_single_read = float(row.get("Reads Pf", row.get("Cluster Count Pf", 0)))
    return {
        "raw_single_read_observations": raw_single_read,
        "pf_single_read_observations": pf_single_read,
        "raw_non_index_read_observations": raw_single_read * non_index_read_count,
        "pf_non_index_read_observations": pf_single_read * non_index_read_count,
        "non_pf_non_index_read_observations": (raw_single_read - pf_single_read)
        * non_index_read_count,
        "interop_percent_q30": float(row.get("% >= Q30", 0)),
        "interop_yield_g": float(row.get("Yield G", 0)),
    }


def numeric_sum(frame: pd.DataFrame, column: str) -> float:
    return float(pd.to_numeric(frame[column], errors="coerce").fillna(0).sum())


def summarize_alignstats(
    path: Path, tables_dir: Path
) -> tuple[pd.DataFrame, dict[str, float | int | str]]:
    alignstats = pd.read_csv(path, sep="\t")
    require_columns(alignstats, REQUIRED_ALIGNSTATS_COLUMNS, str(path))
    validate_alignstats_layout(alignstats, tables_dir)
    summary: dict[str, float | int | str] = {
        "path": str(path),
        "row_count": int(len(alignstats)),
        "column_count": int(len(alignstats.columns)),
        "unique_aligners": ",".join(sorted(alignstats["aligner"].astype(str).unique()))
        if "aligner" in alignstats.columns
        else "",
    }
    for col in REQUIRED_ALIGNSTATS_COLUMNS + [
        "TotalRecords",
        "MappedBases",
        "UnmappedBases",
    ]:
        if col in alignstats.columns:
            summary[col] = numeric_sum(alignstats, col)
    dedup_delta = (
        pd.to_numeric(alignstats["WgsAlignedReads"], errors="coerce")
        - pd.to_numeric(alignstats["WgsCalculatedAlignedReads"], errors="coerce")
        - pd.to_numeric(alignstats["WgsCovDuplicateReads"], errors="coerce")
    )
    summary["max_abs_dedup_reconciliation_delta"] = float(dedup_delta.abs().max())
    summary["mean_wgs_coverage_mean"] = float(
        pd.to_numeric(alignstats["WgsCoverageMean"], errors="coerce").mean()
    )
    pd.DataFrame(summary.items(), columns=["field", "value"]).to_csv(
        tables_dir / "alignstats_aggregate.tsv", sep="\t", index=False
    )
    return alignstats, summary


def validate_alignstats_layout(alignstats: pd.DataFrame, tables_dir: Path) -> None:
    if "sample" not in alignstats.columns or "InputFileName" not in alignstats.columns:
        return
    detail = alignstats[["sample", "aligner", "InputFileName"]].copy()
    detail["lane"] = detail["sample"].astype(str).str.extract(r"-bylane-(\d+)-")[0]
    detail["aggregate_sample"] = (
        detail["sample"]
        .astype(str)
        .str.replace(r"\.sent$", "", regex=True)
        .str.replace(r"-bylane-\d+-", "-bylane-all-", regex=True)
    )
    detail["deduper"] = (
        detail["InputFileName"].astype(str).str.extract(r"/align/[^/]+/([^/]+)/")[0]
    )
    detail["lane"] = pd.to_numeric(detail["lane"], errors="coerce").astype("Int64")
    duplicate_keys = detail.duplicated(
        subset=["aggregate_sample", "lane", "aligner", "deduper"], keep=False
    )
    if duplicate_keys.any():
        duplicated = detail.loc[
            duplicate_keys, ["aggregate_sample", "lane", "aligner", "deduper"]
        ]
        duplicated.to_csv(
            tables_dir / "alignstats_duplicate_lane_keys.tsv", sep="\t", index=False
        )
        raise SystemExit(
            "Duplicate alignstats aggregate_sample/lane/aligner/deduper keys found; "
            f"see {tables_dir / 'alignstats_duplicate_lane_keys.tsv'}"
        )
    grouped = (
        detail.groupby(["aggregate_sample", "aligner", "deduper"], dropna=False)
        .agg(
            lanes=(
                "lane",
                lambda x: ",".join(str(int(v)) for v in sorted(x.dropna().unique())),
            ),
            row_count=("lane", "count"),
        )
        .reset_index()
    )
    grouped["has_exact_lanes_1_to_8"] = grouped["lanes"] == "1,2,3,4,5,6,7,8"
    grouped.to_csv(
        tables_dir / "alignstats_lane_group_validation.tsv", sep="\t", index=False
    )
    bad = grouped[~grouped["has_exact_lanes_1_to_8"]]
    if not bad.empty:
        raise SystemExit(
            "Some alignstats sample groups do not have exactly lanes 1..8; "
            f"see {tables_dir / 'alignstats_lane_group_validation.tsv'}"
        )


def add_edge(
    edges: list[dict[str, object]],
    source: str,
    target: str,
    value: float,
    unit: str,
    stage: str,
    artifact: str,
    counter: str,
    notes: str = "",
    color: str = "rgba(64, 130, 180, 0.45)",
) -> None:
    if value < 0 and abs(value) < 1e-6:
        value = 0
    if value < 0:
        notes = (
            notes + " " if notes else ""
        ) + "Negative reconciliation value clipped to zero."
        value = 0
    edges.append(
        {
            "source": source,
            "target": target,
            "value": value,
            "unit": unit,
            "stage": stage,
            "source_artifact": artifact,
            "counter_name": counter,
            "notes": notes,
            "color": color,
        }
    )


def build_edges(
    interop: dict[str, float],
    demux: dict[str, float | int | str],
    align: dict[str, float | int | str],
    missing_sources: list[str],
) -> pd.DataFrame:
    edges: list[dict[str, object]] = []
    pf = float(interop["pf_non_index_read_observations"])
    non_pf = float(interop["non_pf_non_index_read_observations"])
    analyzed = float(demux["analyzed_read_equivalents"])
    undetermined = float(demux["undetermined_read_equivalents"])
    align_input = float(align["YieldReads"])
    mapped = float(align["MappedReads"])
    unmapped = float(align["UnmappedReads"])
    wgs = float(align["WgsAlignedReads"])
    effective = float(align["WgsCalculatedAlignedReads"])
    duplicate = float(align["WgsCovDuplicateReads"])

    add_edge(
        edges,
        "Raw non-index read observations",
        "PF read observations",
        pf,
        "reads",
        "interop",
        "interop_summary_total.tsv",
        "Reads Pf * non_index_read_count",
        "InterOp reports per-read cluster observations; multiplied by biological read count.",
    )
    add_edge(
        edges,
        "Raw non-index read observations",
        "Non-PF read observations",
        non_pf,
        "reads",
        "interop",
        "interop_summary_total.tsv",
        "(Reads - Reads Pf) * non_index_read_count",
    )
    add_edge(
        edges,
        "PF read observations",
        "Demuxed assigned sample reads",
        analyzed,
        "reads",
        "demux",
        "Quality_Metrics.csv",
        "sum(Yield / read_cycles), SampleID != Undetermined",
    )
    add_edge(
        edges,
        "PF read observations",
        "Undetermined reads",
        undetermined,
        "reads",
        "demux",
        "Quality_Metrics.csv; Undetermined FASTQ objects",
        "sum(Yield / read_cycles), SampleID == Undetermined",
    )
    demux_residual = pf - analyzed - undetermined
    if abs(demux_residual) > max(1000.0, pf * 1e-9):
        add_edge(
            edges,
            "PF read observations",
            "PF demux reconciliation residual",
            demux_residual,
            "reads",
            "reconciliation",
            "InterOp summary vs Quality_Metrics.csv",
            "PF reads - analyzed reads - undetermined reads",
            "Explicit residual, not reassigned.",
            color="rgba(120, 120, 120, 0.35)",
        )
    add_edge(
        edges,
        "Demuxed assigned sample reads",
        "Alignment input reads",
        align_input,
        "reads",
        "pre_alignment",
        "alignstats_combo_mqc.tsv",
        "YieldReads",
        "Daylily alignstats input reads; not used to infer upstream denominators.",
    )
    pre_align_delta = analyzed - align_input
    if abs(pre_align_delta) > max(1000.0, analyzed * 1e-9):
        add_edge(
            edges,
            "Demuxed assigned sample reads",
            "Pre-alignment reconciliation residual",
            pre_align_delta,
            "reads",
            "pre_alignment",
            "Quality_Metrics.csv vs alignstats_combo_mqc.tsv",
            "BCLConvert analyzed reads - alignstats YieldReads",
            "Residual is explicit; no silent fix was applied.",
            color="rgba(120, 120, 120, 0.35)",
        )
    add_edge(
        edges,
        "Alignment input reads",
        "Mapped reads",
        mapped,
        "reads",
        "alignment",
        "alignstats_combo_mqc.tsv",
        "MappedReads",
    )
    add_edge(
        edges,
        "Alignment input reads",
        "Unmapped reads",
        unmapped,
        "reads",
        "alignment",
        "alignstats_combo_mqc.tsv",
        "UnmappedReads",
    )
    add_edge(
        edges,
        "Mapped reads",
        "WGS aligned reads",
        wgs,
        "reads",
        "alignment",
        "alignstats_combo_mqc.tsv",
        "WgsAlignedReads",
    )
    add_edge(
        edges,
        "Mapped reads",
        "Mapped reads outside WGS accounting",
        mapped - wgs,
        "reads",
        "alignment",
        "alignstats_combo_mqc.tsv",
        "MappedReads - WgsAlignedReads",
    )
    add_edge(
        edges,
        "WGS aligned reads",
        "Duplicate-marked reads",
        duplicate,
        "reads",
        "dedup",
        "alignstats_combo_mqc.tsv",
        "WgsCovDuplicateReads",
    )
    add_edge(
        edges,
        "WGS aligned reads",
        "Effective aligned reads",
        effective,
        "reads",
        "dedup",
        "alignstats_combo_mqc.tsv",
        "WgsCalculatedAlignedReads",
    )

    cov1 = float(align["WgsCoverageBases1"])
    cov10 = float(align["WgsCoverageBases10"])
    cov20 = float(align["WgsCoverageBases20"])
    cov30 = float(align["WgsCoverageBases30"])
    add_edge(
        edges,
        "Covered genomic bases >=1x",
        "Genomic bases 1-9x",
        cov1 - cov10,
        "genomic_bases",
        "effective_coverage",
        "alignstats_combo_mqc.tsv",
        "WgsCoverageBases1 - WgsCoverageBases10",
        "Separate genomic-base component; not converted to reads.",
        color="rgba(62, 150, 120, 0.45)",
    )
    add_edge(
        edges,
        "Covered genomic bases >=1x",
        "Genomic bases 10-19x",
        cov10 - cov20,
        "genomic_bases",
        "effective_coverage",
        "alignstats_combo_mqc.tsv",
        "WgsCoverageBases10 - WgsCoverageBases20",
        "Separate genomic-base component; not converted to reads.",
        color="rgba(62, 150, 120, 0.45)",
    )
    add_edge(
        edges,
        "Covered genomic bases >=1x",
        "Genomic bases 20-29x",
        cov20 - cov30,
        "genomic_bases",
        "effective_coverage",
        "alignstats_combo_mqc.tsv",
        "WgsCoverageBases20 - WgsCoverageBases30",
        "Separate genomic-base component; not converted to reads.",
        color="rgba(62, 150, 120, 0.45)",
    )
    add_edge(
        edges,
        "Covered genomic bases >=1x",
        "Genomic bases >=30x",
        cov30,
        "genomic_bases",
        "effective_coverage",
        "alignstats_combo_mqc.tsv",
        "WgsCoverageBases30",
        "Separate genomic-base component; not converted to reads.",
        color="rgba(62, 150, 120, 0.45)",
    )

    for source in missing_sources:
        if "pre_alignment_filter_metrics" in source:
            add_edge(
                edges,
                "Demuxed assigned sample reads",
                f"missing source data: {source}",
                1.0,
                "visual_placeholder",
                "missing_source",
                source,
                "missing",
                "Grey visual placeholder only; not a read counter.",
                color="rgba(160, 160, 160, 0.35)",
            )

    frame = pd.DataFrame(edges)
    return frame


def write_edges_tsv(edges: pd.DataFrame, output_dir: Path) -> None:
    cols = [
        "source",
        "target",
        "value",
        "unit",
        "stage",
        "source_artifact",
        "counter_name",
        "notes",
    ]
    edges[cols].to_csv(output_dir / f"{REPORT_PREFIX}.tsv", sep="\t", index=False)


def format_percent(value: float, denominator: float) -> str:
    if denominator <= 0:
        return "n/a"
    percent = value / denominator * 100.0
    if abs(percent) >= 1:
        return f"{percent:.2f}%"
    if abs(percent) >= 0.01:
        return f"{percent:.3f}%"
    return f"{percent:.3g}%"


def label_terminal_read_nodes(labels: list[str], visible: pd.DataFrame) -> list[str]:
    read_edges = visible[visible["unit"].astype(str) == "reads"].copy()
    if read_edges.empty:
        return labels

    raw_edges = read_edges[read_edges["source"] == "Raw non-index read observations"]
    raw_input_reads = raw_edges["value"].astype(float).sum()
    if raw_input_reads <= 0:
        return labels

    read_sources = set(read_edges["source"].astype(str))
    terminal_targets = (
        read_edges.groupby("target", as_index=True)["value"].sum().astype(float)
    )
    terminal_targets = terminal_targets[
        ~terminal_targets.index.astype(str).isin(read_sources)
    ]

    rendered = []
    for label in labels:
        if label in terminal_targets.index:
            percent = format_percent(float(terminal_targets.loc[label]), raw_input_reads)
            rendered.append(f"{label}<br>{percent} of raw input reads")
        else:
            rendered.append(label)
    return rendered


def render_sankey(edges: pd.DataFrame, output_dir: Path) -> str:
    import plotly.graph_objects as go

    visible = edges[edges["value"].astype(float) > 0].copy()
    if visible.empty:
        raise SystemExit("No positive Sankey edges were produced.")
    labels = pd.Index(
        pd.concat([visible["source"], visible["target"]]).drop_duplicates()
    ).tolist()
    label_to_idx = {label: idx for idx, label in enumerate(labels)}
    display_labels = label_terminal_read_nodes(labels, visible)
    node_colors = []
    for label in labels:
        if label.startswith("missing source data"):
            node_colors.append("rgba(160, 160, 160, 0.85)")
        elif "genomic bases" in label.lower() or "coverage" in label.lower():
            node_colors.append("rgba(62, 150, 120, 0.85)")
        elif "duplicate" in label.lower() or "effective" in label.lower():
            node_colors.append("rgba(184, 120, 60, 0.85)")
        elif (
            "undetermined" in label.lower()
            or "non-pf" in label.lower()
            or "residual" in label.lower()
        ):
            node_colors.append("rgba(130, 130, 130, 0.85)")
        else:
            node_colors.append("rgba(64, 130, 180, 0.85)")

    custom = (
        visible[["unit", "source_artifact", "counter_name", "notes"]].astype(str).values
    )
    fig = go.Figure(
        data=[
            go.Sankey(
                arrangement="snap",
                node={
                    "pad": 22,
                    "thickness": 20,
                    "line": {"color": "rgba(30,30,30,0.35)", "width": 0.5},
                    "label": display_labels,
                    "color": node_colors,
                },
                link={
                    "source": visible["source"].map(label_to_idx).tolist(),
                    "target": visible["target"].map(label_to_idx).tolist(),
                    "value": visible["value"].astype(float).tolist(),
                    "color": visible["color"].tolist(),
                    "customdata": custom,
                    "hovertemplate": (
                        "%{source.label} -> %{target.label}<br>"
                        "value=%{value:,.0f}<br>"
                        "unit=%{customdata[0]}<br>"
                        "artifact=%{customdata[1]}<br>"
                        "counter=%{customdata[2]}<br>"
                        "%{customdata[3]}<extra></extra>"
                    ),
                },
            )
        ]
    )
    fig.update_layout(
        title_text=(
            f"{REPORT_TITLE}: InterOp -> Demux -> Alignment -> Dedup -> Coverage"
            "<br><sup>Terminal read branches are labeled as percent of raw non-index input reads; genomic-base coverage branches are not converted to reads.</sup>"
        ),
        font={"size": 12, "family": "Inter, Arial, sans-serif"},
        paper_bgcolor="white",
        plot_bgcolor="white",
        width=1800,
        height=980,
        margin={"l": 20, "r": 20, "t": 70, "b": 20},
    )
    html = output_dir / f"{REPORT_PREFIX}.html"
    fig.write_html(str(html), include_plotlyjs="cdn", full_html=True)
    svg_status = "skipped"
    try:
        svg = output_dir / f"{REPORT_PREFIX}.svg"
        fig.write_image(str(svg), width=1800, height=980)
        svg_status = "wrote"
    except Exception as exc:
        (output_dir / f"{REPORT_PREFIX}.svg.skipped.txt").write_text(
            f"SVG export skipped: {type(exc).__name__}: {exc}\n",
            encoding="utf-8",
        )
        svg_status = f"skipped: {type(exc).__name__}: {exc}"
    return svg_status


def found_missing_sources(
    ctx: RunContext, inventory: pd.DataFrame, missing_downloads: list[str]
) -> tuple[list[str], list[str]]:
    found = []
    missing = []
    rels = set()
    if not inventory.empty and "s3_uri" in inventory.columns:
        prefix = ctx.run_s3_uri.rstrip("/") + "/"
        rels = {
            str(uri).removeprefix(prefix)
            for uri in inventory["s3_uri"].astype(str).tolist()
            if str(uri).startswith(prefix)
        }

    for rel in RUN_OBJECTS + STANDARD_INTEROP_OBJECTS:
        local = ctx.local_run / rel
        if local.exists() or rel in rels:
            found.append(rel)
        else:
            missing.append(rel)
    for rel in EXPECTED_MAYBE_MISSING:
        if rel in rels or (ctx.local_run / rel).exists():
            found.append(rel)
        else:
            missing.append(rel)
    for rel in missing_downloads:
        if rel not in missing:
            missing.append(rel)
    return sorted(set(found)), sorted(set(missing))


def write_reconciliation(
    output_dir: Path,
    interop: dict[str, float],
    demux: dict[str, float | int | str],
    align: dict[str, float | int | str],
) -> pd.DataFrame:
    rows = [
        {
            "check": "interop_pf_vs_bclconvert_total_read_equivalents",
            "left": interop["pf_non_index_read_observations"],
            "right": demux["total_read_equivalents"],
            "delta": interop["pf_non_index_read_observations"]
            - float(demux["total_read_equivalents"]),
            "status": "clean",
        },
        {
            "check": "bclconvert_analyzed_vs_alignstats_yield_reads",
            "left": demux["analyzed_read_equivalents"],
            "right": align["YieldReads"],
            "delta": float(demux["analyzed_read_equivalents"])
            - float(align["YieldReads"]),
            "status": "clean",
        },
        {
            "check": "alignstats_yield_vs_mapped_plus_unmapped",
            "left": align["YieldReads"],
            "right": float(align["MappedReads"]) + float(align["UnmappedReads"]),
            "delta": float(align["YieldReads"])
            - float(align["MappedReads"])
            - float(align["UnmappedReads"]),
            "status": "clean",
        },
        {
            "check": "alignstats_wgs_aligned_vs_effective_plus_duplicate",
            "left": align["WgsAlignedReads"],
            "right": float(align["WgsCalculatedAlignedReads"])
            + float(align["WgsCovDuplicateReads"]),
            "delta": float(align["WgsAlignedReads"])
            - float(align["WgsCalculatedAlignedReads"])
            - float(align["WgsCovDuplicateReads"]),
            "status": "clean",
        },
    ]
    frame = pd.DataFrame(rows)
    tolerance = frame["left"].abs().map(lambda value: max(10000.0, value * 1e-6))
    frame.loc[frame["delta"].abs() > tolerance, "status"] = "review"
    frame.to_csv(
        output_dir / "raw_metric_tables" / "reconciliation.tsv", sep="\t", index=False
    )
    return frame


def fmt(value: object) -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    if math.isfinite(number):
        return f"{number:,.0f}" if abs(number) >= 1000 else f"{number:g}"
    return str(value)


def markdown_table(frame: pd.DataFrame, columns: list[str]) -> str:
    if frame.empty:
        return "_None._"
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join(["---"] * len(columns)) + " |",
    ]
    for _, row in frame[columns].iterrows():
        lines.append("| " + " | ".join(str(row[col]) for col in columns) + " |")
    return "\n".join(lines)


def write_inventory_md(
    output_dir: Path,
    ctx: RunContext,
    inventory: pd.DataFrame,
    found: list[str],
    missing: list[str],
) -> None:
    counts = pd.DataFrame(columns=["category", "objects", "bytes"])
    if not inventory.empty and "category" in inventory.columns:
        counts = (
            inventory.assign(
                size_bytes=pd.to_numeric(
                    inventory["size_bytes"], errors="coerce"
                ).fillna(0)
            )
            .groupby("category")
            .agg(objects=("s3_uri", "count"), bytes=("size_bytes", "sum"))
            .reset_index()
        )
    content = [
        f"# Raw Illumina Metrics Inventory: {REPORT_TITLE}",
        "",
        f"- Run prefix: `{ctx.run_s3_uri}`",
        f"- Local metrics source: `{ctx.local_run}`",
        "",
        "## Object Categories",
        "",
        markdown_table(counts, ["category", "objects", "bytes"]),
        "",
        "## Data Sources Found",
        "",
        "\n".join(f"- `{item}`" for item in found) if found else "_None._",
        "",
        "## Data Sources Missing",
        "",
        "\n".join(f"- `{item}`" for item in missing) if missing else "_None._",
        "",
        "## Notes",
        "",
        "- Large raw InterOp binaries are inventoried from S3 and are not mirrored unless they are part of the standard parser subset.",
        "- `Undetermined` FASTQ objects are accounted from the S3 inventory when available.",
    ]
    (output_dir / f"raw_illumina_metrics_inventory_{REPORT_PREFIX}.md").write_text(
        "\n".join(content) + "\n", encoding="utf-8"
    )


def write_report_md(
    output_dir: Path,
    args: argparse.Namespace,
    ctx: RunContext,
    run_meta: dict[str, str],
    interop: dict[str, float],
    demux: dict[str, float | int | str],
    align: dict[str, float | int | str],
    found: list[str],
    missing: list[str],
    reconciliation: pd.DataFrame,
    svg_status: str,
) -> None:
    conclusion = (
        "The river uses actual InterOp, BCLConvert, and alignstats counters. "
        "Raw/PF denominators come from InterOp, demux assigned and undetermined "
        "read equivalents come from BCLConvert `Yield` divided by RunInfo read "
        "cycles, and alignment/dedup/effective reads come from alignstats. "
        "Missing pre-alignment filter metrics are shown as an explicit grey placeholder."
    )
    commands = [f"python {' '.join(sys.argv)}"] + ctx.commands
    content = [
        f"# {REPORT_TITLE}",
        "",
        "## Executive Conclusion",
        "",
        conclusion,
        "",
        "## Exact Data Sources Found",
        "",
        "\n".join(f"- `{item}`" for item in found) if found else "_None._",
        "",
        "## Exact Data Sources Missing",
        "",
        "\n".join(f"- `{item}`" for item in missing) if missing else "_None._",
        "",
        "## Commands Run",
        "",
        "\n".join(f"- `{cmd}`" for cmd in commands),
        "",
        "## Illumina Run Identity",
        "",
        f"- Run folder: `{ctx.run_s3_uri}`",
        f"- Instrument: `{run_meta.get('instrument', '')}`",
        f"- Run ID: `{run_meta.get('run_id', '')}`",
        f"- Flowcell ID: `{run_meta.get('flowcell', '')}`",
        f"- Lane count: `{run_meta.get('lane_count', '')}`",
        f"- Flowcell type: `{run_meta.get('flowcell_type', '')}`",
        f"- Read structure: `{run_meta.get('read_structure', '')}`",
        "",
        "## InterOp Summary",
        "",
        f"- Raw non-index read observations: {fmt(interop['raw_non_index_read_observations'])}",
        f"- PF non-index read observations: {fmt(interop['pf_non_index_read_observations'])}",
        f"- Non-PF non-index read observations: {fmt(interop['non_pf_non_index_read_observations'])}",
        f"- InterOp percent Q30: {interop['interop_percent_q30']:.4g}",
        "",
        "## Demux/BCLConvert Summary",
        "",
        f"- FASTQ rows: {fmt(demux['fastq_list_rows'])}",
        f"- Analyzed samples: {fmt(demux['analyzed_unique_samples'])}",
        f"- Analyzed sample-lanes: {fmt(demux['analyzed_sample_lanes'])}",
        f"- Undetermined lanes: {fmt(demux['undetermined_lanes'])}",
        f"- Analyzed read equivalents: {fmt(demux['analyzed_read_equivalents'])}",
        f"- Undetermined read equivalents: {fmt(demux['undetermined_read_equivalents'])}",
        f"- Analyzed PF non-index bases: {fmt(demux['analyzed_yield_bases'])}",
        f"- Undetermined PF non-index bases: {fmt(demux['undetermined_yield_bases'])}",
        f"- Undetermined FASTQ objects: {fmt(demux['undetermined_fastq_objects'])}",
        "",
        "## Pre-Alignment Filter Summary",
        "",
        "- No standalone pre-alignment filter metrics file was found. The diagram shows this as explicit missing source data.",
        "- BCLConvert assigned reads do not fully reconcile to alignstats `YieldReads`; the residual is shown explicitly and no hidden correction was applied.",
        "",
        "## Alignstats-Derived Post-Alignment Summary",
        "",
        f"- Alignstats rows: {fmt(align['row_count'])}",
        f"- Alignstats columns: {fmt(align['column_count'])}",
        f"- Yield reads: {fmt(align['YieldReads'])}",
        f"- Mapped reads: {fmt(align['MappedReads'])}",
        f"- Unmapped reads: {fmt(align['UnmappedReads'])}",
        f"- WGS aligned reads: {fmt(align['WgsAlignedReads'])}",
        f"- Duplicate reads: {fmt(align['WgsCovDuplicateReads'])}",
        f"- Effective aligned reads: {fmt(align['WgsCalculatedAlignedReads'])}",
        f"- Sum of lane-level WGS coverage means: {float(align['WgsCoverageMean']):.6g}",
        f"- Mean of per-row WGS coverage means: {float(align['mean_wgs_coverage_mean']):.6g}",
        "",
        "## Reconciliation Table",
        "",
        markdown_table(reconciliation, ["check", "left", "right", "delta", "status"]),
        "",
        "## Denominator Caveats",
        "",
        "- InterOp `Reads` and `Reads Pf` are per-biological-read cluster observations; the report multiplies by the number of non-index reads to compare with R1+R2 BCLConvert and alignstats read counts.",
        "- BCLConvert `Quality_Metrics.csv` `Yield` is bases, not read records; read equivalents are computed as `Yield / RunInfo non-index read cycles` and are kept auditable in the TSV outputs.",
        "- Alignstats read counters are post-CRAM/alignment counters and are not used to infer raw sequencer or demux denominators.",
        "- Coverage threshold counters are genomic bases, not reads. They are rendered as a separate Sankey component and are not converted to read counts.",
        "- Coverage threshold counters are summed across lane-level analyses; they are not equivalent to a merged-sample genome coverage distribution.",
        "- Duplicate marking was lane-scoped in this by-lane run, so duplicate/effective read totals are sums of lane-level doppelmark results.",
        "",
        "## Visualization Export",
        "",
        f"- HTML: `{output_dir / (REPORT_PREFIX + '.html')}`",
        f"- SVG export: {svg_status}",
        "- Terminal read branch labels show percent of raw non-index input reads. Genomic-base coverage branches are kept separate and are not converted to read percentages.",
        "",
        "## Final Recommended Next Actions",
        "",
        "- Review the grey missing-source placeholder for pre-alignment filters and decide whether a real filter/report file exists elsewhere.",
        "- If a DRAGEN/BCLConvert demultiplex stats report is produced later, rerun the script and confirm it replaces missing demux-detail placeholders.",
        "- Keep the TSV edge table with the HTML so denominator and unit choices remain inspectable.",
    ]
    (output_dir / f"{REPORT_PREFIX}.md").write_text(
        "\n".join(content) + "\n", encoding="utf-8"
    )


def main() -> None:
    global REPORT_PREFIX, REPORT_TITLE
    args = parse_args()
    REPORT_PREFIX = re.sub(r"[^A-Za-z0-9._-]+", "_", args.report_prefix).strip("._-")
    if not REPORT_PREFIX:
        raise SystemExit("--report-prefix must contain at least one safe filename character.")
    REPORT_TITLE = args.report_title.strip() or "Illumina Read-Fate River"
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    tables_dir = output_dir / "raw_metric_tables"
    tables_dir.mkdir(parents=True, exist_ok=True)

    alignstats_path = args.alignstats_combo
    if not alignstats_path.exists():
        raise SystemExit(f"Missing alignstats combo file: {alignstats_path}")
    run_s3_uri = args.run_s3_uri
    bucket, prefix = parse_s3_uri(run_s3_uri)

    if args.skip_fetch:
        local_run, existing_tables = existing_metrics_source(output_dir, args.local_run_dir)
    else:
        local_run = output_dir / "source_run_subset"
        existing_tables = None

    ctx = RunContext(
        bucket=bucket,
        prefix=prefix,
        run_s3_uri=run_s3_uri,
        local_run=local_run,
        tables_dir=tables_dir,
        existing_tables_dir=existing_tables,
        commands=[],
    )

    missing_downloads: list[str] = []
    if args.skip_fetch:
        ctx.commands.append(f"reuse downloaded metrics from {ctx.local_run}")
        inventory = copy_existing_inventory(ctx)
    else:
        inventory, missing_downloads = fetch_raw_metrics(ctx, args.profile, args.region)

    run_meta = parse_run_metadata(ctx)
    demux = summarize_bclconvert(ctx, inventory)
    interop_tables = load_or_write_interop_tables(ctx, output_dir)
    non_index_read_count = len(biological_read_cycles(ctx))
    interop = summarize_interop(interop_tables, non_index_read_count)
    _alignstats, align = summarize_alignstats(alignstats_path, tables_dir)
    found, missing = found_missing_sources(ctx, inventory, missing_downloads)
    edges = build_edges(interop, demux, align, missing)
    write_edges_tsv(edges, output_dir)
    reconciliation = write_reconciliation(output_dir, interop, demux, align)
    svg_status = render_sankey(edges, output_dir)
    write_inventory_md(output_dir, ctx, inventory, found, missing)
    write_report_md(
        output_dir,
        args,
        ctx,
        run_meta,
        interop,
        demux,
        align,
        found,
        missing,
        reconciliation,
        svg_status,
    )
    print(f"Wrote {output_dir / (REPORT_PREFIX + '.html')}")
    print(f"Wrote {output_dir / (REPORT_PREFIX + '.tsv')}")
    print(f"Wrote {output_dir / (REPORT_PREFIX + '.md')}")
    print(f"Wrote {output_dir / ('raw_illumina_metrics_inventory_' + REPORT_PREFIX + '.md')}")
    print(f"SVG export: {svg_status}")


if __name__ == "__main__":
    main()
