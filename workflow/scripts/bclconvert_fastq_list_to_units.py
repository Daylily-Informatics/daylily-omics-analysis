#!/usr/bin/env python3
"""Build a generated units table from BCL Convert fastq_list.csv."""

from __future__ import annotations

import argparse
import csv
import re
from collections import OrderedDict
from pathlib import Path


UNITS_HEADER = [
    "RUNID",
    "SAMPLEID",
    "EXPERIMENTID",
    "LANEID",
    "BARCODEID",
    "LIBPREP",
    "SEQ_VENDOR",
    "SEQ_PLATFORM",
    "ILMN_R1_PATH",
    "ILMN_R2_PATH",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--fastq-list", required=True)
    parser.add_argument("--sample-sheet-rows", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--libprep", default="PCR-FREE")
    parser.add_argument("--seq-vendor", default="ILMN")
    parser.add_argument("--seq-platform-override", default="")
    parser.add_argument("--units-out", required=True)
    return parser.parse_args()


def normalize_key(value: str) -> str:
    text = str(value).strip().upper()
    return re.sub(r"[^A-Z0-9]+", "_", text)


def load_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"ERROR: {path} has no header row.")
        rows = []
        for row in reader:
            cleaned = {normalize_key(key): (value or "").strip() for key, value in row.items() if key}
            if any(cleaned.values()):
                rows.append(cleaned)
        return rows


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise SystemExit(f"ERROR: {path} has no header row.")
        rows = []
        for row in reader:
            cleaned = {normalize_key(key): (value or "").strip() for key, value in row.items() if key}
            if any(cleaned.values()):
                rows.append(cleaned)
        return rows


def normalize_platform(value: str) -> str:
    text = (value or "").strip()
    if not text:
        raise SystemExit("ERROR: Unable to determine SEQ_PLATFORM from the sample sheet row.")

    token = re.sub(r"[^A-Za-z0-9]+", "", text).lower()
    if "novaseq" in token:
        return "NOVASEQ"
    if "nextseq" in token:
        return "NEXTSEQ"
    if "miseq" in token:
        return "MISEQ"
    if "hiseq" in token:
        return "HISEQ"
    if "miniseq" in token:
        return "MINISEQ"
    return re.sub(r"[^A-Za-z0-9]+", "", text).upper()


def join_key(lane: str, sample_id: str) -> tuple[str, str]:
    return (str(lane).strip(), str(sample_id).strip())


def first_nonempty(*values: str) -> str:
    for value in values:
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def build_sample_sheet_index(rows: list[dict[str, str]]) -> OrderedDict[tuple[str, str], dict[str, str]]:
    index: OrderedDict[tuple[str, str], dict[str, str]] = OrderedDict()
    for row in rows:
        lane = first_nonempty(row.get("LANE"))
        sample_id = first_nonempty(row.get("SAMPLE_ID"))
        if not lane or not sample_id:
            raise SystemExit(f"ERROR: sample sheet row is missing LANE or SAMPLE_ID: {row}")
        if lane != "*":
            try:
                if int(lane) <= 0:
                    raise ValueError
            except ValueError:
                raise SystemExit(f"ERROR: sample sheet row has invalid LANE {lane!r}: {row}") from None
        key = join_key(lane, sample_id)
        if key in index:
            existing = index[key]
            raise SystemExit(
                "ERROR: sample sheet rows must be unique per (LANE, SAMPLE_ID) for generated units; "
                f"found duplicate rows for lane {lane!r} sample {sample_id!r}: {existing} / {row}"
            )
        index[key] = row
    return index


def match_sample_row(
    sample_index: OrderedDict[tuple[str, str], dict[str, str]], lane: str, sample_id: str
) -> dict[str, str] | None:
    exact = sample_index.get(join_key(lane, sample_id))
    if exact is not None:
        return exact
    return sample_index.get(join_key("*", sample_id))


def index_combo(index1: str, index2: str) -> str:
    parts = [part for part in [index1.strip(), index2.strip()] if part]
    return "".join(parts)


def main() -> int:
    args = parse_args()
    fastq_path = Path(args.fastq_list)
    rows_path = Path(args.sample_sheet_rows)
    out_path = Path(args.units_out)

    sample_rows = load_tsv(rows_path)
    sample_index = build_sample_sheet_index(sample_rows)
    fastq_rows = load_csv(fastq_path)

    out_path.parent.mkdir(parents=True, exist_ok=True)

    seen: set[tuple[str, str]] = set()
    with out_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=UNITS_HEADER, delimiter="\t", lineterminator="\n")
        writer.writeheader()

        for row in fastq_rows:
            sample_id = first_nonempty(row.get("RGSM"), row.get("SAMPLE_ID"), row.get("SAMPLEID"))
            if not sample_id or sample_id.lower() == "undetermined":
                continue

            lane = first_nonempty(row.get("LANE"))
            if not lane:
                raise SystemExit(f"ERROR: fastq_list row is missing Lane: {row}")

            sample_row = match_sample_row(sample_index, lane, sample_id)
            if sample_row is None:
                raise SystemExit(
                    f"ERROR: fastq_list.csv contains known sample {sample_id!r} in lane {lane!r} "
                    "but no matching parsed sample-sheet row was found."
                )

            read1 = first_nonempty(row.get("READ1FILE"), row.get("READ1_FILE"), row.get("READ1"))
            read2 = first_nonempty(row.get("READ2FILE"), row.get("READ2_FILE"), row.get("READ2"))
            if not read1 or not read2:
                raise SystemExit(
                    f"ERROR: fastq_list row for sample {sample_id!r} lane {lane!r} is missing FASTQ paths."
                )

            index1 = first_nonempty(sample_row.get("INDEX"))
            index2 = first_nonempty(sample_row.get("INDEX2"))
            barcode_combo = index_combo(index1, index2)
            rgid = first_nonempty(row.get("RGID"))
            experiment_id = rgid if rgid else barcode_combo
            barcode_id = barcode_combo if barcode_combo else rgid
            seq_platform = (
                normalize_platform(args.seq_platform_override)
                if args.seq_platform_override.strip()
                else normalize_platform(first_nonempty(sample_row.get("INSTRUMENT_PLATFORM")))
            )

            unique_key = (lane, sample_id)
            if unique_key in seen:
                continue
            seen.add(unique_key)

            output_row = {
                "RUNID": args.run_id,
                "SAMPLEID": sample_id,
                "EXPERIMENTID": experiment_id,
                "LANEID": lane,
                "BARCODEID": barcode_id,
                "LIBPREP": args.libprep,
                "SEQ_VENDOR": args.seq_vendor,
                "SEQ_PLATFORM": seq_platform,
                "ILMN_R1_PATH": read1,
                "ILMN_R2_PATH": read2,
            }
            writer.writerow(output_row)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
