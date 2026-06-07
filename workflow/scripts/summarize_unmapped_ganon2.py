#!/usr/bin/env python3
"""Summarize Ganon2 classification of human-unmapped reads for MultiQC."""

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
    "read_set",
    "database",
    "read_limit",
    "input_fastq",
    "input_fastq_reads",
    "ganon2_report",
    "ganon2_rep",
    "reads_processed",
    "reads_classified",
    "classified_pct",
    "reads_unclassified",
    "unclassified_pct",
    "top_target",
    "top_rank",
    "top_taxon",
    "top_taxon_reads",
    "top_taxon_pct",
]


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


def _parse_rep_counts(path: Path) -> tuple[int, int]:
    _require_file(path, "Ganon2 rep")
    classified: int | None = None
    unclassified: int | None = None
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.startswith("#total_"):
                continue
            fields = line.strip().split()
            if len(fields) < 2:
                raise ValueError(f"Malformed Ganon2 total line in {path}: {line!r}")
            if fields[0] == "#total_classified":
                classified = int(fields[-1])
            elif fields[0] == "#total_unclassified":
                unclassified = int(fields[-1])
    if classified is None or unclassified is None:
        raise ValueError(
            "Ganon2 rep must contain #total_classified and #total_unclassified "
            f"lines: {path}"
        )
    return classified, unclassified


def _parse_tre(path: Path) -> list[dict[str, str | int | float]]:
    _require_file(path, "Ganon2 tree report")
    records: list[dict[str, str | int | float]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 9:
                raise ValueError(
                    f"Expected nine tab-delimited Ganon2 .tre fields at "
                    f"{path}:{line_number}; saw {len(fields)}"
                )
            rank, target, lineage, name, unique, shared, children, cumulative, pct = fields
            records.append(
                {
                    "rank": rank.strip(),
                    "target": target.strip(),
                    "lineage": lineage.strip(),
                    "name": name.strip(),
                    "unique": int(unique.strip()),
                    "shared": int(shared.strip()),
                    "children": int(children.strip()),
                    "cumulative": int(cumulative.strip()),
                    "pct": float(pct.strip()),
                }
            )
    return records


def _top_taxon(records: list[dict[str, str | int | float]]) -> dict[str, str | int | float]:
    excluded_ranks = {"", "root", "unclassified", "no rank"}
    candidates = [
        record
        for record in records
        if str(record["rank"]).lower() not in excluded_ranks
        and str(record["target"]) not in {"", "0", "1", "unclassified"}
        and int(record["cumulative"]) > 0
    ]
    if not candidates:
        return {
            "target": "NA",
            "rank": "NA",
            "name": "NA",
            "cumulative": 0,
            "pct": 0.0,
        }
    return max(
        candidates,
        key=lambda record: (
            int(record["cumulative"]),
            int(record["unique"]),
            int(record["shared"]),
            str(record["name"]),
        ),
    )


def _percent(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "0.0000"
    return f"{(numerator / denominator) * 100:.4f}"


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
        raise ValueError("--database must be an explicit Ganon2 database prefix")
    if str(args.read_limit).strip() != "all":
        raise ValueError("--read-limit must be 'all' for full-unmapped mode")
    read_set = _read_set(args.read_set)

    fastq = Path(args.unmapped_fastq)
    report = Path(args.ganon2_report)
    rep = Path(args.ganon2_rep)
    fastq_reads = _count_fastq_reads(fastq)
    classified, unclassified = _parse_rep_counts(rep)
    processed = classified + unclassified
    records = _parse_tre(report)
    top = _top_taxon(records)
    if fastq_reads > 0 and processed == 0:
        raise ValueError(
            "Ganon2 rep had zero classified and unclassified reads for "
            f"non-empty FASTQ: {rep}"
        )

    return {
        "Sample": args.sample,
        "base_sample": args.base_sample,
        "aligner": args.aligner,
        "deduper": args.deduper,
        "classifier": "ganon2",
        "status": "no_unmapped_reads" if fastq_reads == 0 else "ok",
        "read_set": read_set,
        "database": args.database,
        "read_limit": "all",
        "input_fastq": str(fastq),
        "input_fastq_reads": str(fastq_reads),
        "ganon2_report": str(report),
        "ganon2_rep": str(rep),
        "reads_processed": str(processed),
        "reads_classified": str(classified),
        "classified_pct": _percent(classified, processed),
        "reads_unclassified": str(unclassified),
        "unclassified_pct": _percent(unclassified, processed),
        "top_target": str(top["target"]),
        "top_rank": str(top["rank"]),
        "top_taxon": str(top["name"]),
        "top_taxon_reads": str(top["cumulative"]),
        "top_taxon_pct": f"{float(top['pct']):.4f}",
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
    parser.add_argument("--ganon2-report", required=True)
    parser.add_argument("--ganon2-rep", required=True)
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
