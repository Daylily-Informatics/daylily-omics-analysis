#!/usr/bin/env python3
"""Merge lane-split BCL Convert outputs into the standard DayOA result tree."""

from __future__ import annotations

import argparse
import csv
import os
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane-fastq-root", required=True)
    parser.add_argument("--final-fastq-dir", required=True)
    parser.add_argument("--report-dir", required=True)
    parser.add_argument("--lanes", required=True)
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
        return fieldnames, [dict(row) for row in reader]


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    if not fieldnames:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def merge_report(lane_dirs: list[Path], report_name: str, dest: Path, *, required: bool) -> None:
    merged_header: list[str] | None = None
    merged_rows: list[dict[str, str]] = []
    for lane_dir in lane_dirs:
        header, rows = read_csv(lane_dir / "Reports" / report_name, required=required)
        if not header:
            continue
        if merged_header is None:
            merged_header = header
        elif header != merged_header:
            raise SystemExit(f"ERROR: {report_name} header mismatch in {lane_dir}")
        merged_rows.extend(rows)
    if merged_header is None:
        if required:
            raise SystemExit(f"ERROR: no lane reports found for {report_name}")
        return
    write_csv(dest, merged_header, merged_rows)


def move_lane_fastqs(lane_dirs: list[Path], final_fastq_dir: Path) -> dict[str, str]:
    moved: dict[str, str] = {}
    by_name: dict[str, str] = {}
    final_fastq_dir.mkdir(parents=True, exist_ok=True)
    for lane_dir in lane_dirs:
        if not lane_dir.is_dir():
            raise SystemExit(f"ERROR: missing lane output directory: {lane_dir}")
        for src in sorted(lane_dir.rglob("*.fastq.gz")):
            rel = src.relative_to(lane_dir)
            if rel.parts and rel.parts[0] == "Reports":
                continue
            dst = final_fastq_dir / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists():
                raise SystemExit(f"ERROR: refusing to overwrite merged FASTQ: {dst}")
            src_text = str(src)
            src_abs = str(src.resolve())
            os.replace(src, dst)
            dst_text = str(dst)
            moved[src_text] = dst_text
            moved[src_abs] = dst_text
            by_name[src.name] = dst_text
    moved.update({f"__BASENAME__/{name}": path for name, path in by_name.items()})
    return moved


def copy_lane_artifacts(lane_dirs: list[Path], report_dir: Path) -> None:
    by_lane_root = report_dir / "by_lane"
    for lane_dir in lane_dirs:
        lane_dest = by_lane_root / lane_dir.name
        lane_dest.mkdir(parents=True, exist_ok=True)
        for child in sorted(lane_dir.iterdir()):
            if child.is_file() and child.name.endswith(".fastq.gz"):
                continue
            dest = lane_dest / child.name
            if child.is_dir():
                if dest.exists():
                    shutil.rmtree(dest)
                shutil.copytree(child, dest, ignore=shutil.ignore_patterns("*.fastq.gz"))
            elif child.is_file():
                shutil.copy2(child, dest)


def rewrite_fastq_path(value: str, lane_dirs: list[Path], moved: dict[str, str]) -> str:
    text = str(value or "").strip()
    if not text:
        return text
    if text in moved:
        return moved[text]
    resolved = str(Path(text).resolve())
    if resolved in moved:
        return moved[resolved]
    basename_key = "__BASENAME__/" + Path(text).name
    if basename_key in moved:
        return moved[basename_key]
    for lane_dir in lane_dirs:
        candidate = lane_dir / text
        if str(candidate) in moved:
            return moved[str(candidate)]
        candidate_resolved = str(candidate.resolve())
        if candidate_resolved in moved:
            return moved[candidate_resolved]
    if text.endswith(".fastq.gz"):
        raise SystemExit(f"ERROR: FASTQ listed by BCL Convert was not produced for merge: {text}")
    return text


def merge_fastq_list(lane_dirs: list[Path], dest: Path, moved: dict[str, str]) -> None:
    merged_header: list[str] | None = None
    merged_rows: list[dict[str, str]] = []
    for lane_dir in lane_dirs:
        header, rows = read_csv(lane_dir / "Reports" / "fastq_list.csv", required=True)
        if merged_header is None:
            merged_header = header
        elif header != merged_header:
            raise SystemExit(f"ERROR: fastq_list.csv header mismatch in {lane_dir}")
        for row in rows:
            for key in ("Read1File", "Read2File", "READ1FILE", "READ2FILE", "Read1_File", "Read2_File"):
                if key in row:
                    row[key] = rewrite_fastq_path(row[key], lane_dirs, moved)
            merged_rows.append(row)
    if merged_header is None:
        raise SystemExit("ERROR: no lane fastq_list.csv files found")
    write_csv(dest, merged_header, merged_rows)


def main() -> int:
    args = parse_args()
    lanes = [lane for lane in args.lanes.split(",") if lane]
    if not lanes:
        raise SystemExit("ERROR: no BCL lanes were provided to merge")

    lane_fastq_root = Path(args.lane_fastq_root)
    final_fastq_dir = Path(args.final_fastq_dir)
    report_dir = Path(args.report_dir)
    lane_dirs = [lane_fastq_root / lane for lane in lanes]
    report_dir.mkdir(parents=True, exist_ok=True)
    log_path = Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as log:
        print(f"lane_merge_lanes: {','.join(lanes)}", file=log)
        print(f"lane_merge_root: {lane_fastq_root}", file=log)
        print(f"final_fastq_dir: {final_fastq_dir}", file=log)

    moved = move_lane_fastqs(lane_dirs, final_fastq_dir)
    copy_lane_artifacts(lane_dirs, report_dir)
    merge_fastq_list(lane_dirs, report_dir / "fastq_list.csv", moved)
    merge_report(lane_dirs, "Demultiplex_Stats.csv", report_dir / "Demultiplex_Stats.csv", required=True)
    merge_report(lane_dirs, "Top_Unknown_Barcodes.csv", report_dir / "Top_Unknown_Barcodes.csv", required=False)
    merge_report(lane_dirs, "Index_Hopping_Counts.csv", report_dir / "Index_Hopping_Counts.csv", required=False)
    Path(args.done).parent.mkdir(parents=True, exist_ok=True)
    Path(args.done).touch()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
