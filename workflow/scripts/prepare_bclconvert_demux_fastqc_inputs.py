#!/usr/bin/env python3
"""Prepare collision-safe FastQC inputs for BCL Convert demux FASTQs."""

from __future__ import annotations

import argparse
import csv
import os
import re
from pathlib import Path


FIELDS = [
    "Sample",
    "run_id",
    "lane",
    "rgsm",
    "rgid",
    "read",
    "source_fastq",
    "fastqc_input",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fastq-list", required=True, nargs="+")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--manifest-out", required=True)
    parser.add_argument("--multiqc-out", required=True)
    parser.add_argument("--allow-report-root-remap", action="store_true")
    return parser.parse_args()


def clean_token(value: object, default: str = "NA") -> str:
    text = str(value if value is not None else "").strip()
    if text == "":
        text = default
    text = re.sub(r"\s+", "_", text)
    text = re.sub(r"[^A-Za-z0-9._+-]+", "_", text)
    text = re.sub(r"_+", "_", text)
    return text.strip("._-") or default


def first_nonempty(*values: object) -> str:
    for value in values:
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def read_fastq_list(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise SystemExit(f"ERROR: {path} has no header row.")
        rows = [{key: (value or "").strip() for key, value in row.items() if key} for row in reader]
    rows = [row for row in rows if any(row.values())]
    if not rows:
        raise SystemExit(f"ERROR: {path} has no data rows.")
    return rows


def report_root_remap(path: Path, fastq_list: Path) -> Path | None:
    if not path.is_absolute() or fastq_list.parent.name != "Reports":
        return None
    candidate = (fastq_list.parent.parent / path.name).resolve()
    if candidate.exists():
        return candidate
    return None


def resolve_fastq(value: str, fastq_list: Path, *, allow_report_root_remap: bool = False) -> Path:
    text = str(value or "").strip()
    if not text:
        raise SystemExit("ERROR: fastq_list.csv contains a blank FASTQ path.")
    path = Path(text)
    if not path.is_absolute():
        path = (fastq_list.parent / path).resolve()
    if not path.exists() and allow_report_root_remap:
        remapped = report_root_remap(path, fastq_list)
        if remapped is not None:
            return remapped
    if not path.exists():
        raise SystemExit(f"ERROR: FASTQ listed by BCL Convert does not exist: {path}")
    return path


def output_path_for(input_dir: Path, sample: str) -> Path:
    return input_dir / f"{sample}.fastq.gz"


def link_fastq(source: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink() or dest.exists():
        if dest.is_symlink() and Path(os.readlink(dest)) == source:
            return
        raise SystemExit(f"ERROR: refusing to overwrite existing FastQC input path: {dest}")
    dest.symlink_to(source)


def write_tsv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    args = parse_args()
    input_dir = Path(args.input_dir)
    run_id = clean_token(args.run_id)

    seen_samples: set[str] = set()
    seen_sources: set[Path] = set()
    rows_out: list[dict[str, str]] = []

    for fastq_list_arg in args.fastq_list:
        fastq_list = Path(fastq_list_arg)
        for row in read_fastq_list(fastq_list):
            lane = clean_token(first_nonempty(row.get("Lane"), row.get("LANE")))
            rgsm = clean_token(first_nonempty(row.get("RGSM"), row.get("SampleID"), row.get("Sample_ID")))
            rgid = clean_token(first_nonempty(row.get("RGID"), row.get("ReadGroup"), row.get("RG")))
            if not lane or lane == "NA":
                raise SystemExit(f"ERROR: fastq_list row is missing Lane: {row}")
            if not rgsm or rgsm == "NA":
                raise SystemExit(f"ERROR: fastq_list row is missing RGSM/SampleID: {row}")

            for read_name, fastq_key in (("R1", "Read1File"), ("R2", "Read2File")):
                source = resolve_fastq(
                    first_nonempty(row.get(fastq_key), row.get(fastq_key.upper())),
                    fastq_list,
                    allow_report_root_remap=args.allow_report_root_remap,
                )
                sample = ".".join([run_id, f"L{lane}", rgsm, rgid, read_name])
                if sample in seen_samples:
                    raise SystemExit(
                        "ERROR: BCL Convert demux FastQC sample identifier collision: "
                        f"{sample}. The fastq_list.csv rows must identify unique run/lane/sample/RG/read values."
                    )
                if source in seen_sources:
                    raise SystemExit(
                        "ERROR: BCL Convert demux FastQC source FASTQ is listed more than once: "
                        f"{source}"
                    )
                seen_samples.add(sample)
                seen_sources.add(source)
                dest = output_path_for(input_dir, sample)
                link_fastq(source, dest)
                rows_out.append(
                    {
                        "Sample": sample,
                        "run_id": run_id,
                        "lane": lane,
                        "rgsm": rgsm,
                        "rgid": rgid,
                        "read": read_name,
                        "source_fastq": str(source),
                        "fastqc_input": str(dest),
                    }
                )

    if not rows_out:
        raise SystemExit("ERROR: no BCL Convert demux FASTQs were prepared for FastQC.")

    write_tsv(Path(args.manifest_out), rows_out)
    write_tsv(Path(args.multiqc_out), rows_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
