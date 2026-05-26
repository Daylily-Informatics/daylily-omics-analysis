#!/usr/bin/env python3
"""Validate and normalize Illumina BCL Convert sample sheets."""

from __future__ import annotations

import argparse
import csv
import io
import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = ("Header", "Reads", "BCLConvert_Settings", "BCLConvert_Data")
ROW_COLUMNS = (
    "RUN_NAME",
    "INSTRUMENT_PLATFORM",
    "SOFTWARE_VERSION",
    "OVERRIDE_CYCLES",
    "LANE",
    "SAMPLE_ID",
    "INDEX",
    "INDEX2",
    "SAMPLE_PROJECT",
    "SAMPLE_NAME",
    "SOURCE_ROW",
)

SECTION_RE = re.compile(r"^\[(?P<name>[^\]]+)\]")


class SampleSheetError(RuntimeError):
    """Raised when the sample sheet fails validation."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate and normalize a BCL Convert sample sheet."
    )
    parser.add_argument("--sample-sheet", required=True, help="Input sample sheet CSV")
    parser.add_argument("--samples-tsv", required=True, help="Reference samples.tsv")
    parser.add_argument(
        "--normalized-out",
        required=True,
        help="Path to write the normalized sample sheet CSV",
    )
    parser.add_argument(
        "--rows-out",
        required=True,
        help="Path to write parsed sample-sheet rows as TSV",
    )
    parser.add_argument(
        "--runtime-version",
        "--pinned-runtime-version",
        dest="runtime_version",
        default="",
        help="Pinned BCL Convert runtime version used for warning-only comparisons",
    )
    parser.add_argument(
        "--sampleproject-subdirectories",
        default="false",
        help="Require Sample_Project values when true.",
    )
    parser.add_argument(
        "--warnings-out",
        default="",
        help="Optional path to write validation warnings.",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    raise SampleSheetError(message)


def load_sample_ids(samples_tsv: str) -> set[str]:
    with open(samples_tsv, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            fail(f"samples.tsv is empty: {samples_tsv}")

        header_map = {name.strip().upper(): name for name in reader.fieldnames if name}
        sample_col = header_map.get("SAMPLEID") or header_map.get("SAMPLE_ID")
        if sample_col is None:
            fail("samples.tsv must contain a SAMPLEID or SAMPLE_ID column")

        sample_ids: set[str] = set()
        for row in reader:
            sample_id = (row.get(sample_col) or "").strip()
            if sample_id:
                sample_ids.add(sample_id)

    if not sample_ids:
        fail(f"samples.tsv contains no SAMPLEID values: {samples_tsv}")
    return sample_ids


def read_sections(sample_sheet: str) -> list[dict[str, object]]:
    sections: list[dict[str, object]] = []
    current: dict[str, object] | None = None

    with open(sample_sheet, encoding="utf-8-sig") as handle:
        for lineno, raw_line in enumerate(handle, start=1):
            line = raw_line.rstrip("\r\n")
            stripped = line.strip()

            if not stripped:
                if current is not None:
                    current["content"].append((lineno, line))
                continue

            match = SECTION_RE.match(stripped)
            if match:
                if current is not None:
                    sections.append(current)
                current = {
                    "name": match.group("name").strip(),
                    "start_line": lineno,
                    "content": [],
                }
                continue

            if current is None:
                fail(f"unexpected content before first section at line {lineno}")

            current["content"].append((lineno, line))

    if current is not None:
        sections.append(current)

    if not sections:
        fail(f"sample sheet is empty: {sample_sheet}")
    return sections


def parse_key_value_section(section: dict[str, object]) -> dict[str, str]:
    values: dict[str, str] = {}
    content = section["content"]
    assert isinstance(content, list)

    for lineno, line in content:
        if not line.strip():
            continue
        row = next(csv.reader([line]))
        if not row:
            continue
        key = row[0].strip()
        value = ",".join(row[1:]).strip() if len(row) > 1 else ""
        if not key:
            fail(f"empty key in [{section['name']}] at line {lineno}")
        values[key] = value

    if not values:
        fail(f"required section [{section['name']}] is empty")
    return values


def parse_table_section(
    section: dict[str, object],
) -> tuple[list[str], list[tuple[int, dict[str, str]]]]:
    content = section["content"]
    assert isinstance(content, list)

    header: list[str] | None = None
    rows: list[tuple[int, dict[str, str]]] = []

    for lineno, line in content:
        if not line.strip():
            continue
        row = next(csv.reader([line]))
        if header is None:
            header = [column.strip() for column in row]
            continue

        if len(row) > len(header):
            fail(
                f"row in [{section['name']}] at line {lineno} has more columns than the header"
            )

        values = [cell.strip() for cell in row] + [""] * (len(header) - len(row))
        rows.append((lineno, dict(zip(header, values))))

    if header is None:
        fail(f"required section [{section['name']}] is missing its header row")
    if not rows:
        fail(f"required section [{section['name']}] has no data rows")
    return header, rows


def version_tuple(version: str) -> tuple[int, ...] | None:
    parts = [int(part) for part in re.findall(r"\d+", version or "")]
    return tuple(parts) if parts else None


def boolish(value: str) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def warn_if_newer(sheet_version: str, pinned_version: str) -> str | None:
    sheet_tuple = version_tuple(sheet_version)
    pinned_tuple = version_tuple(pinned_version)
    if sheet_tuple is None or pinned_tuple is None:
        return None

    width = max(len(sheet_tuple), len(pinned_tuple))
    padded_sheet = sheet_tuple + (0,) * (width - len(sheet_tuple))
    padded_pinned = pinned_tuple + (0,) * (width - len(pinned_tuple))
    if padded_sheet > padded_pinned:
        message = (
            "WARNING: sample sheet SoftwareVersion "
            f"{sheet_version} is newer than pinned runtime {pinned_version}"
        )
        print(message, file=sys.stderr)
        return message
    return None


def _csv_line(row: list[str]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="")
    writer.writerow(row)
    return buffer.getvalue()


def write_normalized_sample_sheet(sample_sheet: str, normalized_out: str, runtime_version: str) -> str | None:
    text = Path(sample_sheet).read_text(encoding="utf-8-sig")
    target_version = (runtime_version or "").strip()
    current_section = ""
    rewrite_message: str | None = None
    normalized_lines: list[str] = []

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        match = SECTION_RE.match(stripped)
        if match:
            current_section = match.group("name").strip()
            normalized_lines.append(raw_line)
            continue

        if target_version and current_section == "BCLConvert_Settings" and stripped:
            row = next(csv.reader([raw_line]))
            if row and row[0].strip() == "SoftwareVersion":
                original_version = ",".join(row[1:]).strip() if len(row) > 1 else ""
                if original_version != target_version:
                    raw_line = _csv_line([row[0], target_version])
                    rewrite_message = (
                        "INFO: normalized sample sheet SoftwareVersion "
                        f"from {original_version} to pinned runtime {target_version}"
                    )
                    print(rewrite_message, file=sys.stderr)

        normalized_lines.append(raw_line)

    Path(normalized_out).parent.mkdir(parents=True, exist_ok=True)
    Path(normalized_out).write_text("\n".join(normalized_lines) + "\n", encoding="utf-8")
    return rewrite_message


def main() -> int:
    args = parse_args()
    sample_ids = load_sample_ids(args.samples_tsv)
    sections = read_sections(args.sample_sheet)
    section_map: dict[str, dict[str, object]] = {}

    for section in sections:
        name = str(section["name"])
        if name in section_map:
            fail(f"duplicate section [{name}] in sample sheet")
        section_map[name] = section

    missing = [section for section in REQUIRED_SECTIONS if section not in section_map]
    if missing:
        fail("missing required section(s): " + ", ".join(f"[{name}]" for name in missing))

    header = parse_key_value_section(section_map["Header"])
    _reads = parse_key_value_section(section_map["Reads"])
    settings = parse_key_value_section(section_map["BCLConvert_Settings"])
    data_header, data_rows = parse_table_section(section_map["BCLConvert_Data"])

    if header.get("FileFormatVersion") != "2":
        fail("sample sheet must declare FileFormatVersion,2")

    for field in ("RunName", "InstrumentPlatform"):
        if not header.get(field):
            fail(f"missing required header field: {field}")
    for field in ("SoftwareVersion", "OverrideCycles"):
        if not settings.get(field):
            fail(f"missing required BCLConvert_Settings field: {field}")

    required_data_cols = {"Sample_ID", "Index", "Index2"}
    if not required_data_cols.issubset(set(data_header)):
        fail(
            "BCLConvert_Data must include Sample_ID, Index, and Index2 columns"
        )
    has_lane_column = "Lane" in data_header

    warning_message = warn_if_newer(settings["SoftwareVersion"], args.runtime_version)

    normalized_rows = []
    seen_keys: set[tuple[str, str, str, str]] = set()

    for source_row, row in data_rows:
        lane = (row.get("Lane") or "").strip() if has_lane_column else "*"
        sample_id = (row.get("Sample_ID") or "").strip()
        index = (row.get("Index") or "").strip()
        index2 = (row.get("Index2") or "").strip()
        sample_project = (row.get("Sample_Project") or "").strip()
        sample_name = (row.get("Sample_Name") or "").strip()

        if has_lane_column and not lane:
            fail(f"missing Lane value at line {source_row}")
        if lane != "*":
            try:
                if int(lane) <= 0:
                    fail(f"Lane must be a positive integer at line {source_row}")
            except ValueError as exc:
                raise SampleSheetError(f"Lane must be an integer at line {source_row}") from exc

        if not sample_id:
            fail(f"missing Sample_ID value at line {source_row}")
        if sample_id not in sample_ids:
            fail(f"Sample_ID {sample_id} at line {source_row} is not present in samples.tsv")
        if boolish(args.sampleproject_subdirectories) and not sample_project:
            fail(
                f"Sample_Project is required at line {source_row} when sampleproject_subdirectories=true"
            )

        key = (lane, sample_id, index, index2)
        if key in seen_keys:
            fail(
                "duplicate BCLConvert_Data row for "
                f"(Lane, Sample_ID, Index, Index2)={key}"
            )
        seen_keys.add(key)

        normalized_software_version = args.runtime_version.strip() or settings.get("SoftwareVersion", "")
        normalized_rows.append(
            {
                "RUN_NAME": header.get("RunName", ""),
                "INSTRUMENT_PLATFORM": header.get("InstrumentPlatform", ""),
                "SOFTWARE_VERSION": normalized_software_version,
                "OVERRIDE_CYCLES": settings.get("OverrideCycles", ""),
                "LANE": lane,
                "SAMPLE_ID": sample_id,
                "INDEX": index,
                "INDEX2": index2,
                "SAMPLE_PROJECT": sample_project,
                "SAMPLE_NAME": sample_name,
                "SOURCE_ROW": str(source_row),
            }
        )

    rewrite_message = write_normalized_sample_sheet(args.sample_sheet, args.normalized_out, args.runtime_version)

    out_path = Path(args.rows_out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=ROW_COLUMNS, lineterminator="\n")
        writer.writeheader()
        for row in normalized_rows:
            writer.writerow(row)
    if args.warnings_out:
        warnings_path = Path(args.warnings_out)
        warnings_path.parent.mkdir(parents=True, exist_ok=True)
        warning_messages = [
            message for message in (warning_message, rewrite_message) if message is not None
        ]
        contents = "".join(message + "\n" for message in warning_messages)
        warnings_path.write_text(contents, encoding="utf-8")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SampleSheetError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
