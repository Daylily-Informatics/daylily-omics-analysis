#!/usr/bin/env python3
"""Prepare a lane-specific BCL Convert sample sheet.

The setting-injection path is intentionally dormant unless explicit config
values are supplied. It is present so barcode mismatch and related BCL Convert
settings can be tested without changing normal sample-sheet content.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
from pathlib import Path
from typing import Any


SECTION_RE = re.compile(r"^\[(?P<name>[^\]]+)\]")
ALLOWED_SETTINGS = {
    "AdapterRead1",
    "AdapterRead2",
    "AdapterBehavior",
    "AdapterStringency",
    "MinimumAdapterOverlap",
    "BarcodeMismatchesIndex1",
    "BarcodeMismatchesIndex2",
    "CreateFastqForIndexReads",
    "MinimumTrimmedReadLength",
    "MaskShortReads",
    "OverrideCycles",
    "SoftwareVersion",
    "TrimUMI",
    "NoLaneSplitting",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-sheet", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--lane", required=True)
    parser.add_argument("--settings-json", default="{}")
    parser.add_argument("--settings-by-lane-json", default="{}")
    return parser.parse_args()


def normalize_lane(value: str) -> str:
    text = str(value or "").strip()
    if text.upper().startswith("L"):
        text = text[1:]
    return str(int(text))


def load_mapping(text: str, *, label: str) -> dict[str, Any]:
    payload = str(text or "").strip()
    if not payload:
        return {}
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"ERROR: {label} must be a JSON object") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"ERROR: {label} must be a JSON object")
    return value


def canonical_updates(settings: dict[str, Any], *, label: str) -> dict[str, str]:
    updates: dict[str, str] = {}
    for key, value in settings.items():
        canonical = str(key or "").strip()
        if canonical not in ALLOWED_SETTINGS:
            allowed = ", ".join(sorted(ALLOWED_SETTINGS))
            raise SystemExit(f"ERROR: unsupported {label} setting {canonical!r}; allowed: {allowed}")
        if value is None:
            continue
        text = str(value).strip()
        if text:
            updates[canonical] = text
    return updates


def lane_updates(settings_by_lane: dict[str, Any], lane: str) -> dict[str, str]:
    lane_number = normalize_lane(lane)
    candidates = [lane_number, f"L{int(lane_number):03d}", f"l{int(lane_number):03d}"]
    for key in candidates:
        value = settings_by_lane.get(key)
        if value is None:
            continue
        if not isinstance(value, dict):
            raise SystemExit("ERROR: sample_sheet_settings_by_lane values must be JSON objects")
        return canonical_updates(value, label=f"sample_sheet_settings_by_lane[{key}]")
    return {}


def validate_updates(updates: dict[str, str]) -> None:
    for key in ("BarcodeMismatchesIndex1", "BarcodeMismatchesIndex2"):
        if key in updates and updates[key] not in {"0", "1", "2"}:
            raise SystemExit(f"ERROR: {key} must be 0, 1, or 2: {updates[key]}")


def csv_line(row: list[str]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="")
    writer.writerow(row)
    return buffer.getvalue()


def upsert_settings(lines: list[str], updates: dict[str, str]) -> list[str]:
    section_start = None
    section_end = len(lines)
    for index, raw_line in enumerate(lines):
        match = SECTION_RE.match(raw_line.strip())
        if not match:
            continue
        if match.group("name").strip() == "BCLConvert_Settings":
            section_start = index
            continue
        if section_start is not None and index > section_start:
            section_end = index
            break
    if section_start is None:
        raise SystemExit("ERROR: normalized sample sheet lacks [BCLConvert_Settings]")

    remaining = dict(updates)
    for index in range(section_start + 1, section_end):
        if not lines[index].strip():
            continue
        row = next(csv.reader([lines[index]]))
        key = row[0].strip() if row else ""
        if key in remaining:
            lines[index] = csv_line([key, remaining.pop(key)])

    insert_at = section_end
    for key, value in remaining.items():
        lines.insert(insert_at, csv_line([key, value]))
        insert_at += 1
    return lines


def main() -> int:
    args = parse_args()
    global_settings = canonical_updates(
        load_mapping(args.settings_json, label="sample_sheet_settings"),
        label="sample_sheet_settings",
    )
    by_lane = load_mapping(args.settings_by_lane_json, label="sample_sheet_settings_by_lane")
    updates = {**global_settings, **lane_updates(by_lane, args.lane)}
    validate_updates(updates)

    output = Path(args.out)
    lines = Path(args.sample_sheet).read_text(encoding="utf-8-sig").splitlines()
    if updates:
        lines = upsert_settings(lines, updates)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        "prepared_lane_samplesheet "
        f"lane={normalize_lane(args.lane)} "
        f"settings={'<unchanged>' if not updates else json.dumps(updates, sort_keys=True)} "
        f"out={output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
