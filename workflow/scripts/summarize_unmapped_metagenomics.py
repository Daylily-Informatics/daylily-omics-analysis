#!/usr/bin/env python3
"""Summarize Kraken2 classification of human-unmapped reads for MultiQC."""

from __future__ import annotations

import argparse
import csv
import gzip
from pathlib import Path


FIELDNAMES = [
    "Sample",
    "base_sample",
    "aligner",
    "deduper",
    "classifier",
    "status",
    "database",
    "read_limit",
    "input_fastq",
    "input_fastq_reads",
    "kraken_report",
    "kraken_output",
    "reads_processed",
    "reads_classified",
    "classified_pct",
    "reads_unclassified",
    "unclassified_pct",
    "top_taxid",
    "top_rank",
    "top_taxon",
    "top_taxon_reads",
    "top_taxon_pct",
]


def _require_file(path: Path, label: str, *, allow_empty: bool = False) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Required {label} was not found: {path}")
    if path.stat().st_size == 0 and not allow_empty:
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


def _count_kraken_output(path: Path, *, allow_empty: bool = False) -> tuple[int, int]:
    _require_file(path, "Kraken2 output", allow_empty=allow_empty)
    classified = 0
    unclassified = 0
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            status = line.split("\t", 1)[0]
            if status == "C":
                classified += 1
            elif status == "U":
                unclassified += 1
            else:
                raise ValueError(
                    f"Unexpected Kraken2 classification status {status!r} "
                    f"at {path}:{line_number}"
                )
    return classified, unclassified


def _parse_kraken_report(path: Path) -> list[dict[str, str | int | float]]:
    _require_file(path, "Kraken2 report")
    records: list[dict[str, str | int | float]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t", 5)
            if len(fields) != 6:
                raise ValueError(
                    f"Expected six tab-delimited Kraken2 report fields at "
                    f"{path}:{line_number}; saw {len(fields)}"
                )
            percentage, clade_reads, taxon_reads, rank, taxid, name = fields
            records.append(
                {
                    "percentage": float(percentage.strip()),
                    "clade_reads": int(clade_reads.strip()),
                    "taxon_reads": int(taxon_reads.strip()),
                    "rank": rank.strip(),
                    "taxid": taxid.strip(),
                    "name": name.strip(),
                }
            )
    return records


def _top_taxon(records: list[dict[str, str | int | float]]) -> dict[str, str | int | float]:
    candidates = [
        record
        for record in records
        if str(record["rank"]) not in {"U", "R"}
        and str(record["taxid"]) not in {"0", "1"}
        and int(record["clade_reads"]) > 0
    ]
    if not candidates:
        return {
            "taxid": "NA",
            "rank": "NA",
            "name": "NA",
            "clade_reads": 0,
            "percentage": 0.0,
        }
    return max(
        candidates,
        key=lambda record: (
            int(record["clade_reads"]),
            int(record["taxon_reads"]),
            str(record["name"]),
        ),
    )


def _percent(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "0.0000"
    return f"{(numerator / denominator) * 100:.4f}"


def _build_row(args: argparse.Namespace) -> dict[str, str | int]:
    if str(args.database).strip() in {"", "na", "NA", "None"}:
        raise ValueError("--database must be an explicit Kraken2 database path")
    if str(args.read_limit).strip() != "all":
        raise ValueError("--read-limit must be 'all' for full-unmapped mode")

    fastq = Path(args.unmapped_fastq)
    report = Path(args.kraken_report)
    kraken_output = Path(args.kraken_output)
    fastq_reads = _count_fastq_reads(fastq)
    classified, unclassified = _count_kraken_output(
        kraken_output, allow_empty=(fastq_reads == 0)
    )
    processed = classified + unclassified
    records = _parse_kraken_report(report)
    top = _top_taxon(records)
    if fastq_reads > 0 and processed == 0:
        raise ValueError(
            "Kraken2 output had no classified or unclassified reads for "
            f"non-empty FASTQ: {kraken_output}"
        )

    return {
        "Sample": args.sample,
        "base_sample": args.base_sample,
        "aligner": args.aligner,
        "deduper": args.deduper,
        "classifier": "kraken2",
        "status": "no_unmapped_reads" if fastq_reads == 0 else "ok",
        "database": args.database,
        "read_limit": "all",
        "input_fastq": str(fastq),
        "input_fastq_reads": str(fastq_reads),
        "kraken_report": str(report),
        "kraken_output": str(kraken_output),
        "reads_processed": str(processed),
        "reads_classified": str(classified),
        "classified_pct": _percent(classified, processed),
        "reads_unclassified": str(unclassified),
        "unclassified_pct": _percent(unclassified, processed),
        "top_taxid": str(top["taxid"]),
        "top_rank": str(top["rank"]),
        "top_taxon": str(top["name"]),
        "top_taxon_reads": str(top["clade_reads"]),
        "top_taxon_pct": f"{float(top['percentage']):.4f}",
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--base-sample", required=True)
    parser.add_argument("--aligner", required=True)
    parser.add_argument("--deduper", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--read-limit", required=True)
    parser.add_argument("--unmapped-fastq", required=True)
    parser.add_argument("--kraken-report", required=True)
    parser.add_argument("--kraken-output", required=True)
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
