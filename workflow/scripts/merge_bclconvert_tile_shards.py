#!/usr/bin/env python3
"""Merge tile-sharded BCL Convert outputs back to one lane result."""

from __future__ import annotations

import argparse
import csv
import shutil
from collections import OrderedDict, defaultdict
from pathlib import Path


FASTQ_COLUMNS = ("Read1File", "Read2File", "READ1FILE", "READ2FILE", "Read1_File", "Read2_File")
DEMUX_SUM_COLUMNS = {
    "# Reads",
    "# Perfect Index Reads",
    "# One Mismatch Index Reads",
    "# Two Mismatch Index Reads",
    "# of \u2265 Q30 Bases (PF)",
    "QualityScoreSum",
    "Yield",
    "YieldQ30",
    "AdapterBases",
}
DEMUX_DERIVED_COLUMNS = {
    "% Reads",
    "% Perfect Index Reads",
    "% One Index Reads",
    "% Two Index Reads",
    "Mean Quality Score (PF)",
    "% Adapter Bases",
}
UNKNOWN_SUM_COLUMNS = {"# Reads"}
UNKNOWN_DERIVED_COLUMNS = {"% of Unknown Barcodes", "% of All Reads"}
HOPPING_SUM_COLUMNS = {"# Reads"}
HOPPING_DERIVED_COLUMNS = {"% of Hopped Reads", "% of All Reads"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tile-fastq-root", required=True)
    parser.add_argument("--lane-output-dir", required=True)
    parser.add_argument("--report-dir", required=True)
    parser.add_argument("--lane", required=True)
    parser.add_argument("--shards", required=True)
    parser.add_argument("--sample-sheet", required=True)
    parser.add_argument("--lane-sample-sheet", required=True)
    parser.add_argument("--done", required=True)
    parser.add_argument("--log", required=True)
    return parser.parse_args()


def read_csv(path: Path, *, required: bool) -> tuple[list[str], list[dict[str, str]]]:
    if not path.exists():
        if required:
            raise SystemExit(f"ERROR: missing required BCL Convert report: {path}")
        return [], []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        if required and not fieldnames:
            raise SystemExit(f"ERROR: report has no header: {path}")
        rows = [
            {key: (value or "").strip() for key, value in row.items() if key is not None}
            for row in reader
        ]
    return fieldnames, [row for row in rows if any(row.values())]


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def read_shard_report(
    shard_dirs: list[Path],
    filename: str,
    *,
    required: bool,
) -> tuple[list[str], list[tuple[str, Path, dict[str, str]]]]:
    merged_fieldnames: list[str] | None = None
    rows: list[tuple[str, Path, dict[str, str]]] = []
    for shard_dir in shard_dirs:
        report_path = shard_dir / "Reports" / filename
        fieldnames, shard_rows = read_csv(report_path, required=required)
        if not fieldnames:
            continue
        if merged_fieldnames is None:
            merged_fieldnames = fieldnames
        elif fieldnames != merged_fieldnames:
            raise SystemExit(
                f"ERROR: {filename} header mismatch in {report_path}; "
                f"expected {merged_fieldnames}, observed {fieldnames}"
            )
        rows.extend((shard_dir.name, shard_dir, row) for row in shard_rows)
    if required and merged_fieldnames is None:
        raise SystemExit(f"ERROR: no readable {filename} files found under tile shards")
    return merged_fieldnames or [], rows


def number_value(value: str) -> float:
    text = str(value or "").replace(",", "").strip()
    if text == "":
        return 0.0
    try:
        return float(text)
    except ValueError:
        return 0.0


def format_number(value: float) -> str:
    if abs(value - round(value)) < 0.0000001:
        return str(int(round(value)))
    return f"{value:.6f}".rstrip("0").rstrip(".")


def format_percent(numerator: float, denominator: float) -> str:
    if denominator <= 0:
        return "0.00"
    return f"{(100.0 * numerator / denominator):.2f}"


def aggregate_rows(
    fieldnames: list[str],
    tagged_rows: list[tuple[str, Path, dict[str, str]]],
    *,
    sum_columns: set[str],
    derived_columns: set[str],
) -> list[dict[str, str]]:
    if not fieldnames:
        return []
    key_columns = [column for column in fieldnames if column not in sum_columns and column not in derived_columns]
    grouped: OrderedDict[tuple[str, ...], dict[str, str]] = OrderedDict()
    sums: dict[tuple[str, ...], dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for _, _, row in tagged_rows:
        key = tuple(row.get(column, "") for column in key_columns)
        if key not in grouped:
            grouped[key] = {column: row.get(column, "") for column in fieldnames}
        for column in sum_columns:
            if column in fieldnames:
                sums[key][column] += number_value(row.get(column, ""))
    output_rows: list[dict[str, str]] = []
    for key, row in grouped.items():
        merged = dict(row)
        for column, value in sums[key].items():
            merged[column] = format_number(value)
        output_rows.append(merged)
    return output_rows


def recompute_demux_percentages(fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    totals_by_lane_read: dict[tuple[str, str], float] = defaultdict(float)
    for row in rows:
        totals_by_lane_read[(row.get("Lane", ""), row.get("ReadNumber", ""))] += number_value(row.get("# Reads", ""))
    for row in rows:
        reads = number_value(row.get("# Reads", ""))
        lane_read_total = totals_by_lane_read[(row.get("Lane", ""), row.get("ReadNumber", ""))]
        if "% Reads" in fieldnames:
            row["% Reads"] = format_percent(reads, lane_read_total)
        if "% Perfect Index Reads" in fieldnames:
            row["% Perfect Index Reads"] = format_percent(number_value(row.get("# Perfect Index Reads", "")), reads)
        if "% One Index Reads" in fieldnames:
            row["% One Index Reads"] = format_percent(number_value(row.get("# One Mismatch Index Reads", "")), reads)
        if "% Two Index Reads" in fieldnames:
            row["% Two Index Reads"] = format_percent(number_value(row.get("# Two Mismatch Index Reads", "")), reads)
        if "Mean Quality Score (PF)" in fieldnames:
            row["Mean Quality Score (PF)"] = (
                f"{number_value(row.get('QualityScoreSum', '')) / reads:.2f}" if reads > 0 else "0.00"
            )
        if "% Adapter Bases" in fieldnames:
            q30_bases = number_value(row.get("# of \u2265 Q30 Bases (PF)", ""))
            row["% Adapter Bases"] = format_percent(number_value(row.get("AdapterBases", "")), q30_bases)


def recompute_simple_percentages(
    fieldnames: list[str],
    rows: list[dict[str, str]],
    *,
    lane_total_reads: dict[str, float],
    total_percent_column: str,
    all_reads_percent_column: str,
) -> None:
    total_by_lane: dict[str, float] = defaultdict(float)
    for row in rows:
        total_by_lane[row.get("Lane", "")] += number_value(row.get("# Reads", ""))
    for row in rows:
        lane = row.get("Lane", "")
        reads = number_value(row.get("# Reads", ""))
        if total_percent_column in fieldnames:
            row[total_percent_column] = format_percent(reads, total_by_lane[lane])
        if all_reads_percent_column in fieldnames:
            row[all_reads_percent_column] = format_percent(reads, lane_total_reads[lane])


def lane_total_reads(demux_rows: list[dict[str, str]]) -> dict[str, float]:
    totals_by_lane_read: dict[tuple[str, str], float] = defaultdict(float)
    for row in demux_rows:
        totals_by_lane_read[(row.get("Lane", ""), row.get("ReadNumber", ""))] += number_value(row.get("# Reads", ""))
    totals: dict[str, float] = defaultdict(float)
    for (lane, read_number), reads in totals_by_lane_read.items():
        if read_number:
            totals[lane] = max(totals[lane], reads)
        else:
            totals[lane] += reads
    return totals


def resolve_fastq_path(shard_dir: Path, value: str) -> Path:
    text = str(value or "").strip()
    if not text:
        raise SystemExit(f"ERROR: empty FASTQ path in {shard_dir / 'Reports' / 'fastq_list.csv'}")
    candidates = [Path(text), shard_dir / text, shard_dir / Path(text).name]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    matches = sorted(path for path in shard_dir.rglob(Path(text).name) if path.is_file())
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise SystemExit(f"ERROR: FASTQ path is ambiguous for {text} under {shard_dir}")
    raise SystemExit(f"ERROR: FASTQ listed by BCL Convert was not produced: {text} under {shard_dir}")


def output_relative_path(shard_dir: Path, src: Path) -> Path:
    try:
        rel = src.resolve().relative_to(shard_dir.resolve())
    except ValueError:
        rel = Path(src.name)
    if rel.parts and rel.parts[0] == "Reports":
        return Path(src.name)
    return rel


def concatenate_fastqs(dest: Path, sources: list[Path]) -> None:
    if not sources:
        raise SystemExit(f"ERROR: no shard FASTQs were provided for {dest}")
    if dest.exists():
        raise SystemExit(f"ERROR: refusing to overwrite merged tile-shard FASTQ: {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("wb") as out_handle:
        for src in sources:
            with src.open("rb") as in_handle:
                shutil.copyfileobj(in_handle, out_handle, length=1024 * 1024)


def merge_fastq_list(
    fieldnames: list[str],
    tagged_rows: list[tuple[str, Path, dict[str, str]]],
    lane_output_dir: Path,
    report_dir: Path,
) -> None:
    if not fieldnames:
        raise SystemExit("ERROR: no fastq_list.csv headers were found")
    fastq_columns = [column for column in FASTQ_COLUMNS if column in fieldnames]
    if not fastq_columns:
        raise SystemExit("ERROR: fastq_list.csv has no recognized FASTQ path columns")

    row_key_columns = [column for column in fieldnames if column not in fastq_columns]
    merged_rows: OrderedDict[tuple[str, ...], dict[str, str]] = OrderedDict()
    fastq_groups: OrderedDict[tuple[tuple[str, ...], str], dict[str, object]] = OrderedDict()
    for shard_name, shard_dir, row in tagged_rows:
        row_key = tuple(row.get(column, "") for column in row_key_columns)
        if row_key not in merged_rows:
            merged_rows[row_key] = {column: row.get(column, "") for column in fieldnames}
        for column in fastq_columns:
            if not row.get(column):
                continue
            src = resolve_fastq_path(shard_dir, row[column])
            rel = output_relative_path(shard_dir, src)
            dest = lane_output_dir / rel
            group_key = (row_key, column)
            group = fastq_groups.setdefault(group_key, {"dest": dest, "sources": []})
            if group["dest"] != dest:
                raise SystemExit(
                    f"ERROR: inconsistent merged FASTQ destination for row {row_key}, "
                    f"column {column}: {group['dest']} vs {dest}"
                )
            group["sources"].append((shard_name, src))
            merged_rows[row_key][column] = str(dest)

    for group in fastq_groups.values():
        ordered_sources = [src for _, src in sorted(group["sources"], key=lambda item: item[0])]
        concatenate_fastqs(group["dest"], ordered_sources)
    write_csv(report_dir / "fastq_list.csv", fieldnames, list(merged_rows.values()))


def main() -> int:
    args = parse_args()
    shards = [shard for shard in args.shards.split(",") if shard]
    if not shards:
        raise SystemExit("ERROR: no BCL tile shards were provided to merge")
    tile_fastq_root = Path(args.tile_fastq_root)
    lane_output_dir = Path(args.lane_output_dir)
    report_dir = Path(args.report_dir)
    shard_dirs = [tile_fastq_root / args.lane / shard for shard in shards]
    missing_dirs = [str(path) for path in shard_dirs if not path.is_dir()]
    if missing_dirs:
        raise SystemExit("ERROR: missing tile-shard output directories: " + ", ".join(missing_dirs))

    log_path = Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)
    lane_output_dir.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as log:
        print(f"tile_shard_merge_lane: {args.lane}", file=log)
        print(f"tile_shard_merge_shards: {','.join(shards)}", file=log)
        print(f"tile_fastq_root: {tile_fastq_root}", file=log)
        print(f"lane_output_dir: {lane_output_dir}", file=log)

    fastq_fieldnames, fastq_rows = read_shard_report(shard_dirs, "fastq_list.csv", required=True)
    merge_fastq_list(fastq_fieldnames, fastq_rows, lane_output_dir, report_dir)

    demux_fieldnames, demux_tagged_rows = read_shard_report(shard_dirs, "Demultiplex_Stats.csv", required=True)
    demux_rows = aggregate_rows(
        demux_fieldnames,
        demux_tagged_rows,
        sum_columns=DEMUX_SUM_COLUMNS,
        derived_columns=DEMUX_DERIVED_COLUMNS,
    )
    recompute_demux_percentages(demux_fieldnames, demux_rows)
    write_csv(report_dir / "Demultiplex_Stats.csv", demux_fieldnames, demux_rows)

    totals_by_lane = lane_total_reads(demux_rows)
    unknown_fieldnames, unknown_tagged_rows = read_shard_report(shard_dirs, "Top_Unknown_Barcodes.csv", required=False)
    if unknown_fieldnames:
        unknown_rows = aggregate_rows(
            unknown_fieldnames,
            unknown_tagged_rows,
            sum_columns=UNKNOWN_SUM_COLUMNS,
            derived_columns=UNKNOWN_DERIVED_COLUMNS,
        )
        recompute_simple_percentages(
            unknown_fieldnames,
            unknown_rows,
            lane_total_reads=totals_by_lane,
            total_percent_column="% of Unknown Barcodes",
            all_reads_percent_column="% of All Reads",
        )
        write_csv(report_dir / "Top_Unknown_Barcodes.csv", unknown_fieldnames, unknown_rows)

    hopping_fieldnames, hopping_tagged_rows = read_shard_report(shard_dirs, "Index_Hopping_Counts.csv", required=False)
    if hopping_fieldnames:
        hopping_rows = aggregate_rows(
            hopping_fieldnames,
            hopping_tagged_rows,
            sum_columns=HOPPING_SUM_COLUMNS,
            derived_columns=HOPPING_DERIVED_COLUMNS,
        )
        recompute_simple_percentages(
            hopping_fieldnames,
            hopping_rows,
            lane_total_reads=totals_by_lane,
            total_percent_column="% of Hopped Reads",
            all_reads_percent_column="% of All Reads",
        )
        write_csv(report_dir / "Index_Hopping_Counts.csv", hopping_fieldnames, hopping_rows)

    lane_sample_sheet = Path(args.lane_sample_sheet)
    lane_sample_sheet.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.sample_sheet, lane_sample_sheet)
    done_path = Path(args.done)
    done_path.parent.mkdir(parents=True, exist_ok=True)
    done_path.touch()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
