#!/usr/bin/env python3
"""Summarize sourmash gather fingerprints of human-unmapped reads for MultiQC."""

from __future__ import annotations

import argparse
import csv
import gzip
import json
from pathlib import Path


FIELDNAMES = [
    "Sample",
    "base_sample",
    "aligner",
    "deduper",
    "classifier",
    "status",
    "read_set",
    "database",
    "read_limit",
    "input_fastq",
    "input_fastq_reads",
    "sourmash_signature",
    "sourmash_gather_csv",
    "sourmash_ksize",
    "sourmash_scaled",
    "sourmash_moltype",
    "sourmash_threshold_bp",
    "gather_matches",
    "query_bp",
    "query_n_hashes",
    "weighted_found_fraction",
    "unique_intersect_bp",
    "top_name",
    "top_md5",
    "top_filename",
    "top_rank",
    "top_f_unique_weighted",
    "top_f_unique_to_query",
    "top_intersect_bp",
    "top_unique_intersect_bp",
]

GATHER_REQUIRED_COLUMNS = {
    "unique_intersect_bp",
    "intersect_bp",
    "f_unique_to_query",
    "f_unique_weighted",
    "filename",
    "name",
    "md5",
    "gather_result_rank",
    "query_bp",
    "ksize",
    "moltype",
    "scaled",
    "query_n_hashes",
}


def _require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Required {label} was not found: {path}")
    if path.stat().st_size == 0:
        raise ValueError(f"Required {label} is empty: {path}")


def _count_fastq_reads(path: Path) -> int:
    _require_file(path, "FASTQ")
    opener = gzip.open if path.name.endswith(".gz") else open
    line_count = 0
    with opener(path, "rt", encoding="utf-8") as handle:
        for line_count, _line in enumerate(handle, start=1):
            pass
    if line_count % 4 != 0:
        raise ValueError(f"FASTQ line count is not divisible by four: {path}")
    return line_count // 4


def _parse_positive_int(value: str, label: str) -> int:
    parsed = int(str(value).strip())
    if parsed < 1:
        raise ValueError(f"{label} must be >= 1; saw {value!r}")
    return parsed


def _parse_nonnegative_int(value: str, label: str) -> int:
    parsed = int(str(value).strip())
    if parsed < 0:
        raise ValueError(f"{label} must be >= 0; saw {value!r}")
    return parsed


def _parse_gather_csv(path: Path) -> list[dict[str, str]]:
    _require_file(path, "sourmash gather CSV")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ValueError(f"sourmash gather CSV has no header: {path}")
        missing = sorted(GATHER_REQUIRED_COLUMNS - set(reader.fieldnames))
        if missing:
            raise ValueError(
                "sourmash gather CSV is missing required column(s): "
                + ", ".join(missing)
                + f" in {path}"
            )
        return [dict(row) for row in reader]


def _validate_signature(path: Path, fastq_reads: int) -> None:
    _require_file(path, "sourmash signature")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"sourmash signature is not valid JSON: {path}") from exc

    if isinstance(payload, dict):
        status = str(payload.get("dayoa_status", "")).strip()
        signatures = payload.get("signatures")
        if status == "no_unmapped_reads" and fastq_reads != 0:
            raise ValueError(
                "sourmash no_unmapped_reads sentinel is only valid when "
                f"input FASTQ has zero reads: {path}"
            )
        if isinstance(signatures, list):
            if not signatures and fastq_reads != 0:
                raise ValueError(
                    "sourmash signature list is empty for non-empty FASTQ: "
                    f"{path}"
                )
            return
    elif isinstance(payload, list):
        if not payload and fastq_reads != 0:
            raise ValueError(
                f"sourmash signature list is empty for non-empty FASTQ: {path}"
            )
        return

    if fastq_reads != 0:
        raise ValueError(
            "sourmash signature must contain a non-empty signatures list for "
            f"non-empty FASTQ: {path}"
        )


def _float_field(row: dict[str, str], field: str) -> float:
    value = str(row[field]).strip()
    if value == "":
        return 0.0
    return float(value)


def _int_field(row: dict[str, str], field: str) -> int:
    value = str(row[field]).strip()
    if value == "":
        return 0
    return int(float(value))


def _top_gather_row(rows: list[dict[str, str]]) -> dict[str, str] | None:
    if not rows:
        return None
    return min(
        rows,
        key=lambda row: (
            _float_field(row, "gather_result_rank"),
            -_float_field(row, "f_unique_weighted"),
            str(row["name"]),
        ),
    )


def _first_or_zero(rows: list[dict[str, str]], field: str) -> str:
    if not rows:
        return "0"
    value = str(rows[0].get(field, "")).strip()
    return value or "0"


def _read_set(value: str) -> str:
    read_set = str(value).strip()
    allowed = {"s", "p"}
    if read_set not in allowed:
        raise ValueError(
            "--read-set must be one of "
            + ", ".join(sorted(allowed))
            + f"; saw {value!r}"
        )
    return read_set


def _build_row(args: argparse.Namespace) -> dict[str, str]:
    if str(args.database).strip() in {"", "na", "NA", "None"}:
        raise ValueError("--database must be an explicit sourmash database path list")
    if str(args.read_limit).strip() != "all":
        raise ValueError("--read-limit must be 'all' for full-unmapped mode")
    read_set = _read_set(args.read_set)

    ksize = _parse_positive_int(args.sourmash_ksize, "--sourmash-ksize")
    scaled = _parse_positive_int(args.sourmash_scaled, "--sourmash-scaled")
    threshold_bp = _parse_nonnegative_int(
        args.sourmash_threshold_bp, "--sourmash-threshold-bp"
    )
    moltype = str(args.sourmash_moltype).strip()
    if moltype.upper() != "DNA":
        raise ValueError("--sourmash-moltype must be 'DNA'")

    fastq = Path(args.unmapped_fastq)
    signature = Path(args.sourmash_signature)
    gather_csv = Path(args.sourmash_gather_csv)
    fastq_reads = _count_fastq_reads(fastq)
    _validate_signature(signature, fastq_reads)
    gather_rows = _parse_gather_csv(gather_csv)
    top = _top_gather_row(gather_rows)

    weighted_found = sum(_float_field(row, "f_unique_weighted") for row in gather_rows)
    unique_bp = sum(_int_field(row, "unique_intersect_bp") for row in gather_rows)

    if top is None:
        top_fields = {
            "top_name": "NA",
            "top_md5": "NA",
            "top_filename": "NA",
            "top_rank": "NA",
            "top_f_unique_weighted": "0.000000",
            "top_f_unique_to_query": "0.000000",
            "top_intersect_bp": "0",
            "top_unique_intersect_bp": "0",
        }
    else:
        top_fields = {
            "top_name": str(top["name"]).strip() or "NA",
            "top_md5": str(top["md5"]).strip() or "NA",
            "top_filename": str(top["filename"]).strip() or "NA",
            "top_rank": str(top["gather_result_rank"]).strip() or "NA",
            "top_f_unique_weighted": f"{_float_field(top, 'f_unique_weighted'):.6f}",
            "top_f_unique_to_query": f"{_float_field(top, 'f_unique_to_query'):.6f}",
            "top_intersect_bp": str(_int_field(top, "intersect_bp")),
            "top_unique_intersect_bp": str(_int_field(top, "unique_intersect_bp")),
        }

    return {
        "Sample": args.sample,
        "base_sample": args.base_sample,
        "aligner": args.aligner,
        "deduper": args.deduper,
        "classifier": "sourmash_gather",
        "status": "no_unmapped_reads" if fastq_reads == 0 else "ok",
        "read_set": read_set,
        "database": args.database,
        "read_limit": "all",
        "input_fastq": str(fastq),
        "input_fastq_reads": str(fastq_reads),
        "sourmash_signature": str(signature),
        "sourmash_gather_csv": str(gather_csv),
        "sourmash_ksize": str(ksize),
        "sourmash_scaled": str(scaled),
        "sourmash_moltype": "DNA",
        "sourmash_threshold_bp": str(threshold_bp),
        "gather_matches": str(len(gather_rows)),
        "query_bp": _first_or_zero(gather_rows, "query_bp"),
        "query_n_hashes": _first_or_zero(gather_rows, "query_n_hashes"),
        "weighted_found_fraction": f"{weighted_found:.6f}",
        "unique_intersect_bp": str(unique_bp),
        **top_fields,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--base-sample", required=True)
    parser.add_argument("--aligner", required=True)
    parser.add_argument("--deduper", required=True)
    parser.add_argument("--read-set", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--read-limit", required=True)
    parser.add_argument("--unmapped-fastq", required=True)
    parser.add_argument("--sourmash-signature", required=True)
    parser.add_argument("--sourmash-gather-csv", required=True)
    parser.add_argument("--sourmash-ksize", required=True)
    parser.add_argument("--sourmash-scaled", required=True)
    parser.add_argument("--sourmash-moltype", required=True)
    parser.add_argument("--sourmash-threshold-bp", required=True)
    parser.add_argument("--output", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    row = _build_row(args)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerow(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
