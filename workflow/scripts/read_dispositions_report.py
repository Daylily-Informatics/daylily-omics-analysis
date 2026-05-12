#!/usr/bin/env python3
"""Join Illumina run metrics with alignstats into read disposition tables."""

from __future__ import annotations

import argparse
import html
import math
import re
import sys
from pathlib import Path
from typing import Any

import pandas as pd


ANALYZED_SAMPLE_LANES = "bclconvert_quality_metrics_by_analyzed_sample_lane.tsv"

ALIGNSTATS_REQUIRED_COLUMNS = [
    "sample",
    "YieldReads",
    "MappedReads",
    "UnmappedReads",
    "WgsAlignedReads",
    "WgsCalculatedAlignedReads",
    "WgsCovDuplicateReads",
]

DISPOSITION_COUNT_COLUMNS = [
    "bclconvert_assigned_reads",
    "alignment_input_reads",
    "human_mapped_reads",
    "human_unmapped_reads",
    "wgs_aligned_reads",
    "duplicate_reads",
    "effective_aligned_reads",
    "not_represented_in_human_aligned_stream_reads",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metrics-dir", required=True, type=Path)
    parser.add_argument("--alignstats-combo", required=True, type=Path)
    parser.add_argument("--samples-tsv", required=True, type=Path)
    parser.add_argument("--units-tsv", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--mqc-out", required=True, type=Path)
    return parser.parse_args()


def fail(message: str) -> None:
    raise SystemExit(message)


def require_file(path: Path, label: str) -> None:
    if not path.exists():
        fail(f"Missing required {label}: {path}")


def require_columns(frame: pd.DataFrame, columns: list[str], source: Path) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        fail(f"{source} is missing required columns: {', '.join(missing)}")


def read_tsv(path: Path, label: str) -> pd.DataFrame:
    require_file(path, label)
    return pd.read_csv(path, sep="\t")


def clean_component(value: Any) -> str:
    text = str(value or "").strip()
    if text.lower() in {"", "na", "none", "nan"}:
        return ""
    return re.sub(r"\s+", "", text)


def normalize_key(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value or "").lower())


def truthy(value: Any) -> bool:
    if value in [None, ""]:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "y", "positive", "pos"}


def build_unit_id(row: pd.Series) -> str:
    if "analysis_unit_uid" in row.index and clean_component(row["analysis_unit_uid"]):
        return clean_component(row["analysis_unit_uid"])
    parts = [
        clean_component(row.get("RUNID", "")),
        clean_component(row.get("SAMPLEID", "")),
        clean_component(row.get("EXPERIMENTID", "")),
        clean_component(row.get("LANEID", "")),
        clean_component(row.get("BARCODEID", "")),
        clean_component(row.get("LIBPREP", "")),
        clean_component(row.get("SEQ_VENDOR", "")),
        clean_component(row.get("SEQ_PLATFORM", "")),
    ]
    parts = [part for part in parts if part]
    if not parts:
        fail("Unable to construct analysis unit identifier from units.tsv row.")
    return "-".join(parts)


def read_units(path: Path) -> pd.DataFrame:
    units = read_tsv(path, "units.tsv")
    require_columns(units, ["SAMPLEID", "LANEID"], path)
    units = units.copy()
    units["analysis_unit_uid"] = units.apply(build_unit_id, axis=1)
    units["sample_key"] = units["SAMPLEID"].map(normalize_key)
    units["lane"] = pd.to_numeric(units["LANEID"], errors="coerce")
    if units["lane"].isna().any():
        bad = sorted(units.loc[units["lane"].isna(), "LANEID"].astype(str).unique())
        fail(f"units.tsv contains non-numeric LANEID values: {', '.join(bad)}")
    units["lane"] = units["lane"].astype(int)
    units["unit_match_key"] = units["analysis_unit_uid"].map(normalize_key)
    if units["unit_match_key"].duplicated().any():
        dupes = sorted(
            units.loc[units["unit_match_key"].duplicated(), "analysis_unit_uid"]
            .astype(str)
            .unique()
        )
        fail(f"Duplicate analysis unit identifiers in units.tsv: {', '.join(dupes)}")
    return units


def read_samples(path: Path) -> pd.DataFrame:
    samples = read_tsv(path, "samples.tsv")
    require_columns(samples, ["SAMPLEID"], path)
    samples = samples.copy()
    samples["sample_key"] = samples["SAMPLEID"].map(normalize_key)
    samples["cohort"] = samples.apply(sample_cohort, axis=1)
    return samples[["SAMPLEID", "sample_key", "cohort"]].drop_duplicates()


def sample_cohort(row: pd.Series) -> str:
    positive_cols = [
        "IS_POSITIVE_CONTROL",
        "POSITIVE_CONTROL",
        "IS_POS_CTRL",
        "POS_CTRL",
        "truth_sample",
    ]
    negative_cols = [
        "IS_NEGATIVE_CONTROL",
        "NEGATIVE_CONTROL",
        "IS_NEG_CTRL",
        "NEG_CTRL",
    ]
    for col in positive_cols:
        if col in row.index and truthy(row[col]):
            return "positive_control"
    for col in negative_cols:
        if col in row.index and truthy(row[col]):
            return "negative_control"
    for col in ["SAMPLESOURCE", "SAMPLE_TYPE", "sample_type"]:
        if col in row.index and clean_component(row[col]):
            return str(row[col]).strip()
    return "samples"


def read_bcl_metrics(metrics_dir: Path) -> pd.DataFrame:
    path = metrics_dir / ANALYZED_SAMPLE_LANES
    bcl = read_tsv(path, ANALYZED_SAMPLE_LANES)
    require_columns(bcl, ["SampleID", "Lane", "read_equivalents"], path)
    bcl = bcl.copy()
    bcl["sample_key"] = bcl["SampleID"].map(normalize_key)
    bcl["lane"] = pd.to_numeric(bcl["Lane"], errors="coerce")
    bcl["read_equivalents"] = pd.to_numeric(bcl["read_equivalents"], errors="coerce")
    if bcl[["lane", "read_equivalents"]].isna().any().any():
        fail(f"{path} contains non-numeric Lane or read_equivalents values.")
    bcl["lane"] = bcl["lane"].astype(int)
    return bcl


def deduper_from_input_path(row: pd.Series) -> str:
    if "deduper" in row.index and clean_component(row["deduper"]):
        return clean_component(row["deduper"])
    if "ddup" in row.index and clean_component(row["ddup"]):
        return clean_component(row["ddup"])
    input_path = str(row.get("InputFileName", ""))
    match = re.search(r"/align/[^/]+/([^/]+)/", input_path)
    if match:
        return match.group(1)
    return "NA"


def sample_base(row: pd.Series) -> str:
    sample = str(row["sample"])
    aligner = clean_component(row.get("aligner", ""))
    if aligner and sample.endswith(f".{aligner}"):
        return sample[: -(len(aligner) + 1)]
    return re.sub(r"\.[A-Za-z0-9_-]+$", "", sample)


def map_alignstats_to_units(alignstats: pd.DataFrame, units: pd.DataFrame) -> pd.DataFrame:
    unit_by_key = units.set_index("unit_match_key", drop=False)
    unit_keys = sorted(unit_by_key.index.tolist(), key=len, reverse=True)
    bcl_sample_keys = set(units["sample_key"])

    mapped_rows: list[dict[str, Any]] = []
    missing: list[str] = []

    for _, row in alignstats.iterrows():
        base = sample_base(row)
        base_key = normalize_key(base)
        unit_row: pd.Series | None = None
        if base_key in unit_by_key.index:
            unit_row = unit_by_key.loc[base_key]
        else:
            contained = [key for key in unit_keys if key and key in base_key]
            if len(contained) == 1:
                unit_row = unit_by_key.loc[contained[0]]

        if unit_row is None:
            sample_matches = sorted(key for key in bcl_sample_keys if key and key in base_key)
            lane_match = re.search(r"(?:^|[-_.])L?0*([0-9]{1,2})(?:[-_.]|$)", base)
            if len(sample_matches) == 1 and lane_match:
                sample_key = sample_matches[0]
                lane = int(lane_match.group(1))
                unit_subset = units[
                    (units["sample_key"] == sample_key)
                    & (units["lane"] == lane)
                ]
                if len(unit_subset) == 1:
                    unit_row = unit_subset.iloc[0]

        if unit_row is None:
            missing.append(str(row["sample"]))
            continue

        out = row.to_dict()
        out["analysis_unit_uid"] = unit_row["analysis_unit_uid"]
        out["SampleID"] = unit_row["SAMPLEID"]
        out["sample_key"] = unit_row["sample_key"]
        out["lane"] = int(unit_row["lane"])
        out["aligner"] = clean_component(row.get("aligner", "")) or "NA"
        out["deduper"] = deduper_from_input_path(row)
        mapped_rows.append(out)

    if missing:
        fail(
            "Unable to map alignstats rows to units.tsv SAMPLEID/LANEID: "
            + ", ".join(sorted(set(missing)))
        )
    return pd.DataFrame(mapped_rows)


def read_alignstats(path: Path, units: pd.DataFrame) -> pd.DataFrame:
    alignstats = read_tsv(path, "alignstats_combo_mqc.tsv")
    require_columns(alignstats, ALIGNSTATS_REQUIRED_COLUMNS, path)
    alignstats = alignstats.copy()
    for col in ALIGNSTATS_REQUIRED_COLUMNS:
        if col == "sample":
            continue
        alignstats[col] = pd.to_numeric(alignstats[col], errors="coerce")
    numeric_cols = [col for col in ALIGNSTATS_REQUIRED_COLUMNS if col != "sample"]
    if alignstats[numeric_cols].isna().any().any():
        fail(f"{path} contains non-numeric alignstats count values.")
    return map_alignstats_to_units(alignstats, units)


def pct(numerator: float, denominator: float) -> float:
    if denominator == 0:
        return math.nan
    return numerator / denominator * 100.0


def build_dispositions(
    bcl: pd.DataFrame, alignstats: pd.DataFrame, samples: pd.DataFrame
) -> pd.DataFrame:
    joined = bcl.merge(
        alignstats,
        on=["sample_key", "lane"],
        how="left",
        suffixes=("_bcl", "_alignstats"),
        validate="one_to_many",
    )
    missing = joined[joined["sample"].isna()][["SampleID_bcl", "lane"]].drop_duplicates()
    if not missing.empty:
        missing_pairs = [
            f"{row.SampleID_bcl}/lane{int(row.lane)}" for row in missing.itertuples()
        ]
        fail(
            "Missing alignstats rows for BCLConvert analyzed sample-lanes: "
            + ", ".join(sorted(missing_pairs))
        )

    joined = joined.merge(samples[["sample_key", "cohort"]], on="sample_key", how="left")
    joined["cohort"] = joined["cohort"].fillna("samples")

    dispositions = pd.DataFrame(
        {
            "sample": joined["SampleID_bcl"],
            "lane": joined["lane"].astype(int),
            "analysis_unit_uid": joined["analysis_unit_uid"],
            "alignstats_sample": joined["sample"],
            "aligner": joined["aligner"],
            "deduper": joined["deduper"],
            "cohort": joined["cohort"],
            "bclconvert_assigned_reads": joined["read_equivalents"],
            "alignment_input_reads": joined["YieldReads"],
            "human_mapped_reads": joined["MappedReads"],
            "human_unmapped_reads": joined["UnmappedReads"],
            "wgs_aligned_reads": joined["WgsAlignedReads"],
            "duplicate_reads": joined["WgsCovDuplicateReads"],
            "effective_aligned_reads": joined["WgsCalculatedAlignedReads"],
        }
    )
    dispositions["not_represented_in_human_aligned_stream_reads"] = (
        dispositions["bclconvert_assigned_reads"] - dispositions["alignment_input_reads"]
    )
    dispositions["yield_minus_mapped_unmapped_delta"] = (
        dispositions["alignment_input_reads"]
        - dispositions["human_mapped_reads"]
        - dispositions["human_unmapped_reads"]
    )
    dispositions["wgs_dedup_reconciliation_delta"] = (
        dispositions["wgs_aligned_reads"]
        - dispositions["effective_aligned_reads"]
        - dispositions["duplicate_reads"]
    )

    dispositions["alignment_input_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["alignment_input_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["human_mapped_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["human_mapped_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["human_unmapped_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["human_unmapped_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["wgs_aligned_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["wgs_aligned_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["duplicate_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["duplicate_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["effective_aligned_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["effective_aligned_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["not_represented_in_human_aligned_stream_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["not_represented_in_human_aligned_stream_reads"],
            dispositions["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    dispositions["human_mapped_pct_of_alignment_input"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["human_mapped_reads"],
            dispositions["alignment_input_reads"],
            strict=True,
        )
    ]
    dispositions["human_unmapped_pct_of_alignment_input"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["human_unmapped_reads"],
            dispositions["alignment_input_reads"],
            strict=True,
        )
    ]
    dispositions["effective_aligned_pct_of_wgs_aligned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["effective_aligned_reads"],
            dispositions["wgs_aligned_reads"],
            strict=True,
        )
    ]
    dispositions["duplicate_pct_of_wgs_aligned"] = [
        pct(n, d)
        for n, d in zip(
            dispositions["duplicate_reads"],
            dispositions["wgs_aligned_reads"],
            strict=True,
        )
    ]
    return dispositions.sort_values(["sample", "lane", "aligner", "deduper"])


def aggregate_rows(frame: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    grouped = frame.groupby(group_cols, dropna=False)[DISPOSITION_COUNT_COLUMNS].sum().reset_index()
    grouped["sample_lanes"] = (
        frame.groupby(group_cols, dropna=False)[["sample", "lane"]]
        .apply(lambda part: int(part.drop_duplicates().shape[0]))
        .values
    )
    grouped["alignment_input_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(grouped["alignment_input_reads"], grouped["bclconvert_assigned_reads"], strict=True)
    ]
    grouped["human_mapped_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(grouped["human_mapped_reads"], grouped["bclconvert_assigned_reads"], strict=True)
    ]
    grouped["human_unmapped_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(grouped["human_unmapped_reads"], grouped["bclconvert_assigned_reads"], strict=True)
    ]
    grouped["effective_aligned_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(grouped["effective_aligned_reads"], grouped["bclconvert_assigned_reads"], strict=True)
    ]
    grouped["not_represented_in_human_aligned_stream_pct_of_assigned"] = [
        pct(n, d)
        for n, d in zip(
            grouped["not_represented_in_human_aligned_stream_reads"],
            grouped["bclconvert_assigned_reads"],
            strict=True,
        )
    ]
    grouped["human_mapped_pct_of_alignment_input"] = [
        pct(n, d)
        for n, d in zip(grouped["human_mapped_reads"], grouped["alignment_input_reads"], strict=True)
    ]
    grouped["human_unmapped_pct_of_alignment_input"] = [
        pct(n, d)
        for n, d in zip(grouped["human_unmapped_reads"], grouped["alignment_input_reads"], strict=True)
    ]
    grouped["effective_aligned_pct_of_wgs_aligned"] = [
        pct(n, d)
        for n, d in zip(grouped["effective_aligned_reads"], grouped["wgs_aligned_reads"], strict=True)
    ]
    grouped["duplicate_pct_of_wgs_aligned"] = [
        pct(n, d)
        for n, d in zip(grouped["duplicate_reads"], grouped["wgs_aligned_reads"], strict=True)
    ]
    return grouped


def cohort_dispositions(frame: pd.DataFrame) -> pd.DataFrame:
    cohort = aggregate_rows(frame, ["cohort", "aligner", "deduper"])
    all_rows = aggregate_rows(frame.assign(cohort="all_samples"), ["cohort", "aligner", "deduper"])
    return pd.concat([cohort, all_rows], ignore_index=True).sort_values(["cohort", "aligner", "deduper"])


def fmt(value: Any) -> str:
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


def markdown_table(frame: pd.DataFrame, columns: list[str], limit: int = 12) -> str:
    if frame.empty:
        return "_None._"
    shown = frame[columns].head(limit)
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join(["---"] * len(columns)) + " |",
    ]
    for _, row in shown.iterrows():
        lines.append("| " + " | ".join(fmt(row[col]) for col in columns) + " |")
    if len(frame) > limit:
        lines.append("| ... | ... | ... | ... | ... | ... | ... | ... |")
    return "\n".join(lines)


def write_mqc(frame: pd.DataFrame, output: Path) -> None:
    rows: list[dict[str, Any]] = []
    metric_cols = [
        "bclconvert_assigned_reads",
        "alignment_input_reads",
        "human_mapped_reads",
        "human_unmapped_reads",
        "effective_aligned_reads",
        "not_represented_in_human_aligned_stream_reads",
        "human_mapped_pct_of_alignment_input",
        "effective_aligned_pct_of_assigned",
    ]
    for _, row in frame.iterrows():
        sample = f"{row['sample']}_L{int(row['lane']):03d}.{row['aligner']}.{row['deduper']}"
        for metric in metric_cols:
            rows.append(
                {
                    "sample": sample,
                    "metric": metric,
                    "value": row[metric],
                    "cohort": row["cohort"],
                    "sample_id": row["sample"],
                    "lane": int(row["lane"]),
                    "aligner": row["aligner"],
                    "deduper": row["deduper"],
                }
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(output, sep="\t", index=False)


def write_report(output_dir: Path, sample_lane: pd.DataFrame, cohort: pd.DataFrame) -> None:
    report_cols = [
        "cohort",
        "aligner",
        "deduper",
        "sample_lanes",
        "bclconvert_assigned_reads",
        "alignment_input_reads",
        "human_mapped_reads",
        "human_unmapped_reads",
        "effective_aligned_reads",
        "not_represented_in_human_aligned_stream_reads",
    ]
    lane_cols = [
        "sample",
        "lane",
        "aligner",
        "deduper",
        "bclconvert_assigned_reads",
        "alignment_input_reads",
        "human_mapped_reads",
        "human_unmapped_reads",
    ]
    content = [
        "# Read Dispositions",
        "",
        "This report reconciles BCLConvert assigned read equivalents with Daylily alignstats counters. "
        "The residual between assigned reads and alignstats `YieldReads` is labeled "
        "`not represented in the human-aligned read stream`; it is not classified as contamination without "
        "an independent classifier source.",
        "",
        "## Cohort Dispositions",
        "",
        markdown_table(cohort, report_cols),
        "",
        "## Sample-Lane Dispositions",
        "",
        markdown_table(sample_lane, lane_cols),
        "",
        "## Reconciliation Notes",
        "",
        "- `human_mapped_reads` and `human_unmapped_reads` come from alignstats and describe reads in the alignment input stream.",
        "- `effective_aligned_reads` is the post-dedup WGS aligned read count from alignstats `WgsCalculatedAlignedReads`.",
        "- `not_represented_in_human_aligned_stream_reads` is `BCLConvert assigned read equivalents - alignstats YieldReads`.",
    ]
    md = output_dir / "read_dispositions.md"
    html_out = output_dir / "read_dispositions.html"
    md.write_text("\n".join(content) + "\n", encoding="utf-8")
    html_body = html.escape("\n".join(content)).replace("\n", "<br>\n")
    html_out.write_text(
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>"
        "Read Dispositions</title></head><body><pre>"
        + html_body
        + "</pre></body></html>\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    bcl = read_bcl_metrics(args.metrics_dir)
    units = read_units(args.units_tsv)
    samples = read_samples(args.samples_tsv)
    alignstats = read_alignstats(args.alignstats_combo, units)

    sample_lane = build_dispositions(bcl, alignstats, samples)
    cohort = cohort_dispositions(sample_lane)

    sample_lane.to_csv(args.output_dir / "sample_lane_dispositions.tsv", sep="\t", index=False)
    cohort.to_csv(args.output_dir / "cohort_dispositions.tsv", sep="\t", index=False)
    write_mqc(sample_lane, args.mqc_out)
    write_report(args.output_dir, sample_lane, cohort)

    print(f"Wrote {args.output_dir / 'sample_lane_dispositions.tsv'}")
    print(f"Wrote {args.output_dir / 'cohort_dispositions.tsv'}")
    print(f"Wrote {args.output_dir / 'read_dispositions.md'}")
    print(f"Wrote {args.output_dir / 'read_dispositions.html'}")
    print(f"Wrote {args.mqc_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
