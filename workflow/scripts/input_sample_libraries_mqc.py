#!/usr/bin/env python3
"""Build a MultiQC custom-data table for DayOA input sample libraries."""

from __future__ import annotations

import csv
import re
from collections.abc import Mapping, Sequence
from pathlib import Path


def _clean_value(value: object) -> str:
    if value is None:
        return ""
    try:
        if bool(value != value):
            return ""
    except TypeError:
        pass
    return str(value)


def _snake_case(name: str) -> str:
    cleaned = re.sub(r"[^0-9A-Za-z]+", "_", str(name).strip()).strip("_")
    return cleaned.lower()


def _deduped_name(name: str, used: set[str], *, prefix: str) -> str:
    candidate = name
    if candidate in used:
        candidate = f"{prefix}_{candidate}"
    if candidate not in used:
        used.add(candidate)
        return candidate
    idx = 2
    while f"{candidate}_{idx}" in used:
        idx += 1
    final_name = f"{candidate}_{idx}"
    used.add(final_name)
    return final_name


def _records_and_columns(
    frame,
    *,
    frame_name: str,
) -> tuple[list[dict[str, str]], list[str]]:
    if hasattr(frame, "columns") and hasattr(frame, "to_dict"):
        columns = [str(column) for column in frame.columns]
        raw_records = frame.to_dict(orient="records")
    elif isinstance(frame, Sequence) and not isinstance(frame, (str, bytes)):
        raw_records = list(frame)
        columns = []
        for row in raw_records:
            if not isinstance(row, Mapping):
                raise ValueError(f"{frame_name} rows must be mappings")
            for column in row:
                column = str(column)
                if column not in columns:
                    columns.append(column)
    else:
        raise ValueError(
            f"{frame_name} must be a pandas DataFrame or a sequence of row mappings"
        )

    records: list[dict[str, str]] = []
    for row in raw_records:
        if not isinstance(row, Mapping):
            raise ValueError(f"{frame_name} rows must be mappings")
        records.append({str(key): _clean_value(value) for key, value in row.items()})
    return records, columns


def _ensure_column(
    records: list[dict[str, str]], columns: list[str], column: str, *, default: str = ""
) -> None:
    if column not in columns:
        columns.append(column)
    for row in records:
        row.setdefault(column, default)


def _require_column(columns: list[str], column: str, *, frame_name: str) -> None:
    if column not in columns:
        raise ValueError(f"{frame_name} is missing {column}")


def _sample_index(sample_records: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    by_sample: dict[str, dict[str, str]] = {}
    duplicate_sampleids: set[str] = set()
    for row in sample_records:
        sampleid = row.get("SAMPLEID", "")
        if sampleid in by_sample:
            duplicate_sampleids.add(sampleid)
        by_sample[sampleid] = row
    if duplicate_sampleids:
        raise ValueError(
            "samples.tsv contains duplicate SAMPLEID values: "
            + ", ".join(sorted(duplicate_sampleids))
        )
    return by_sample


def build_input_sample_libraries_mqc_table(
    *,
    metadata,
    sample_records,
    unit_records,
    added_by_snakemake: bool,
) -> tuple[list[str], list[dict[str, str]]]:
    """Return fieldnames and rows for a MultiQC-ready samples/units union."""
    meta_rows, meta_columns = _records_and_columns(metadata, frame_name="metadata")
    sample_rows, sample_columns = _records_and_columns(
        sample_records, frame_name="sample_records"
    )
    unit_rows, unit_columns = _records_and_columns(
        unit_records, frame_name="unit_records"
    )

    _require_column(meta_columns, "analysis_unit_uid", frame_name="metadata")
    _require_column(sample_columns, "SAMPLEID", frame_name="sample_records")
    _require_column(unit_columns, "SAMPLEID", frame_name="unit_records")
    _ensure_column(sample_rows, sample_columns, "COMMENT")
    _ensure_column(unit_rows, unit_columns, "COMMENT")

    if len(meta_rows) != len(unit_rows):
        raise ValueError(
            "metadata and unit_records row counts differ; cannot assign analysis_unit_id"
        )

    samples_by_id = _sample_index(sample_rows)
    missing_sampleids = sorted(
        {
            row.get("SAMPLEID", "")
            for row in unit_rows
            if row.get("SAMPLEID", "") not in samples_by_id
        }
    )
    if missing_sampleids:
        raise ValueError(
            "units.tsv contains SAMPLEID values missing from samples.tsv: "
            + ", ".join(missing_sampleids)
        )

    fieldnames = ["analysis_unit_id", "Sample", "added_by_snakemake"]
    used = set(fieldnames)
    unit_output_columns: list[tuple[str, str]] = []
    sample_output_columns: list[tuple[str, str]] = []

    for column in unit_columns:
        base_name = "unit_comment" if column == "COMMENT" else _snake_case(column)
        output_name = _deduped_name(base_name, used, prefix="unit")
        fieldnames.append(output_name)
        unit_output_columns.append((column, output_name))

    for column in sample_columns:
        if column == "SAMPLEID":
            continue
        base_name = "sample_comment" if column == "COMMENT" else _snake_case(column)
        output_name = _deduped_name(base_name, used, prefix="sample")
        fieldnames.append(output_name)
        sample_output_columns.append((column, output_name))

    added_value = "true" if added_by_snakemake else "false"
    rows: list[dict[str, str]] = []
    for meta_row, unit_row in zip(meta_rows, unit_rows):
        analysis_unit_id = _clean_value(meta_row.get("analysis_unit_uid", ""))
        if not analysis_unit_id:
            raise ValueError("metadata contains blank analysis_unit_uid values")
        sample_row = samples_by_id[unit_row.get("SAMPLEID", "")]
        output_row = {
            "analysis_unit_id": analysis_unit_id,
            "Sample": analysis_unit_id,
            "added_by_snakemake": added_value,
        }
        for source_column, output_column in unit_output_columns:
            output_row[output_column] = _clean_value(unit_row.get(source_column, ""))
        for source_column, output_column in sample_output_columns:
            output_row[output_column] = _clean_value(sample_row.get(source_column, ""))
        rows.append(output_row)

    return fieldnames, rows


def write_input_sample_libraries_mqc(
    output_path: str | Path,
    *,
    metadata,
    sample_records,
    unit_records,
    added_by_snakemake: bool,
) -> tuple[list[str], list[dict[str, str]]]:
    fieldnames, rows = build_input_sample_libraries_mqc_table(
        metadata=metadata,
        sample_records=sample_records,
        unit_records=unit_records,
        added_by_snakemake=added_by_snakemake,
    )
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return fieldnames, rows
