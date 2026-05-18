"""Parse manifest FASTQ path fields.

DayOA normally stores one path in each FASTQ column. A field may also contain a
CSV-style comma-separated list of paths when one analysis unit should stream
multiple lane FASTQs without first concatenating them.
"""

from __future__ import annotations

import csv

EMPTY_PATH_TOKENS = {"", "na", "none", "null"}


def split_fastq_path_list(value: object) -> list[str]:
    """Return one or more FASTQ paths from a scalar manifest field."""
    if value is None:
        return []

    text = str(value).strip()
    if text.lower() in EMPTY_PATH_TOKENS:
        return []

    try:
        paths = next(csv.reader([text], skipinitialspace=True))
    except csv.Error as exc:
        raise ValueError(f"invalid FASTQ path list {text!r}: {exc}") from exc

    cleaned = [path.strip() for path in paths]
    empty_positions = [
        str(index + 1)
        for index, path in enumerate(cleaned)
        if path.lower() in EMPTY_PATH_TOKENS
    ]
    if empty_positions:
        raise ValueError(
            f"invalid FASTQ path list {text!r}: empty path at position(s) "
            + ", ".join(empty_positions)
        )
    return cleaned


def paired_fastq_path_lists(
    r1_value: object,
    r2_value: object,
    *,
    context: str = "FASTQ path fields",
    require_r2: bool = True,
) -> tuple[list[str], list[str]]:
    """Parse paired FASTQ path fields and validate their cardinality."""
    r1_paths = split_fastq_path_list(r1_value)
    r2_paths = split_fastq_path_list(r2_value)

    if not r1_paths and not r2_paths:
        return [], []
    if not r1_paths:
        raise ValueError(f"{context}: R2 paths were provided without R1 paths")
    if require_r2 and not r2_paths:
        raise ValueError(f"{context}: R1 paths require matching R2 paths")
    if r2_paths and len(r1_paths) != len(r2_paths):
        raise ValueError(
            f"{context}: R1 and R2 path lists must have the same number of entries "
            f"(R1={len(r1_paths)}, R2={len(r2_paths)})"
        )

    return r1_paths, r2_paths
