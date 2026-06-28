"""Parse manifest FASTQ path fields.

DayOA normally stores one path in each FASTQ column. A field may also contain a
CSV-style comma-separated list of paths when one analysis unit should stream
multiple lane FASTQs without first concatenating them.
"""

from __future__ import annotations

import csv
import os
import re
from datetime import datetime, timezone

EMPTY_PATH_TOKENS = {"", "na", "none", "null"}
ONT_RUN_COMPONENT_RE = re.compile(r"^\d{8}_ONT_")
ONT_ACQUISITION_COMPONENT_RE = re.compile(r"^(\d{8})_(\d{4})(?:_|$)")
ONT_FASTQ_CHUNK_RE = re.compile(r"_(\d+)\.fastq\.gz$")


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


def validate_fastq_hour_window(
    use_fq_data_starting_hrs: object,
    use_fq_data_up_to_hrs: object,
) -> tuple[int, int]:
    """Validate and normalize ONT FASTQ elapsed-hour filter bounds."""

    starting_hrs = _strict_int_config(
        use_fq_data_starting_hrs,
        config_key="use-fq_data-starting-hrs",
    )
    up_to_hrs = _strict_int_config(
        use_fq_data_up_to_hrs,
        config_key="use-fq_data-up-to-hrs",
    )

    if starting_hrs <= 0:
        raise ValueError("use-fq_data-starting-hrs must be an integer > 0")
    if up_to_hrs <= starting_hrs:
        raise ValueError(
            "use-fq_data-up-to-hrs must be an integer greater than "
            "use-fq_data-starting-hrs"
        )

    return starting_hrs, up_to_hrs


def filter_ont_fastq_paths_by_hour_window(
    paths: list[str],
    use_fq_data_starting_hrs: object,
    use_fq_data_up_to_hrs: object,
    *,
    timestamp_source: str = "path",
) -> list[str]:
    """Keep ONT FASTQs within the elapsed-hour window for each run/barcode."""

    starting_hrs, up_to_hrs = validate_fastq_hour_window(
        use_fq_data_starting_hrs,
        use_fq_data_up_to_hrs,
    )

    if timestamp_source == "chunk-hour":
        return [
            path
            for path in paths
            if starting_hrs <= ont_fastq_chunk_hour(path) < up_to_hrs
        ]

    parsed_records = [
        {
            "path": path,
            "group": ont_fastq_group_key(path),
            "timestamp": ont_fastq_time(path, timestamp_source=timestamp_source),
        }
        for path in paths
    ]

    group_start_times = {}
    for record in parsed_records:
        group = record["group"]
        timestamp = record["timestamp"]
        if group not in group_start_times or timestamp < group_start_times[group]:
            group_start_times[group] = timestamp

    filtered_paths = []
    for record in parsed_records:
        elapsed_hours = (
            record["timestamp"] - group_start_times[record["group"]]
        ).total_seconds() / 3600.0
        if starting_hrs <= elapsed_hours < up_to_hrs:
            filtered_paths.append(record["path"])

    return filtered_paths


def ont_fastq_group_key(path: str) -> tuple[str, str]:
    """Return the ONT run/barcode grouping key used for elapsed-hour filtering."""

    components = _path_components(path)
    run_id = next(
        (component for component in components if ONT_RUN_COMPONENT_RE.match(component)),
        None,
    )
    barcode = next(
        (
            component
            for component in components
            if component.startswith("barcode") or component == "unclassified"
        ),
        None,
    )

    if run_id is None:
        raise ValueError(f"unable to identify ONT run id in FASTQ path: {path}")
    if barcode is None:
        raise ValueError(f"unable to identify ONT barcode in FASTQ path: {path}")

    return run_id, barcode


def ont_fastq_acquisition_time(path: str) -> datetime:
    """Extract the acquisition start timestamp from an ONT FASTQ path."""

    for component in _path_components(path):
        match = ONT_ACQUISITION_COMPONENT_RE.match(component)
        if match:
            return datetime.strptime("".join(match.groups()), "%Y%m%d%H%M")
    raise ValueError(f"unable to identify ONT acquisition timestamp in FASTQ path: {path}")


def ont_fastq_mtime(path: str) -> datetime:
    """Return the filesystem modification time for a mounted ONT FASTQ path."""

    try:
        timestamp = os.path.getmtime(path)
    except OSError as exc:
        raise ValueError(f"unable to stat ONT FASTQ path for mtime: {path}") from exc
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).replace(tzinfo=None)


def ont_fastq_time(path: str, *, timestamp_source: str = "path") -> datetime:
    """Return the configured timestamp used for ONT elapsed-hour filtering."""

    if timestamp_source == "path":
        return ont_fastq_acquisition_time(path)
    if timestamp_source == "mtime":
        return ont_fastq_mtime(path)
    if timestamp_source == "chunk-hour":
        raise ValueError(
            "chunk-hour timestamp source produces elapsed-hour values, not timestamps"
        )
    raise ValueError(f"unsupported ONT FASTQ timestamp source: {timestamp_source}")


def ont_fastq_chunk_hour(path: str) -> int:
    """Extract the ONT FASTQ chunk suffix used as the production-hour proxy."""

    filename = str(path).rstrip("/").split("/")[-1]
    match = ONT_FASTQ_CHUNK_RE.search(filename)
    if not match:
        raise ValueError(f"unable to identify ONT FASTQ chunk hour in path: {path}")
    return int(match.group(1))


def _strict_int_config(value: object, *, config_key: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{config_key} must be an integer, not boolean")
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if not re.fullmatch(r"[+-]?\d+", text):
        raise ValueError(f"{config_key} must be an integer")
    return int(text)


def _path_components(path: str) -> list[str]:
    return [component for component in str(path).split("/") if component]
