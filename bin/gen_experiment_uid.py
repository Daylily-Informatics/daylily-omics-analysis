#!/usr/bin/env python3
"""
exid.py

Emit and decode EXIDs of the form: YYMMDDHHMMSSZ (UTC).

Usage:
  ./exid.py emit
  ./exid.py decode 260213083015Z
  ./exid.py decode 260213083015Z --tz America/Los_Angeles
"""

from __future__ import annotations

import argparse
import csv
import shutil
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


EXID_FMT = "%y%m%d%H%M%SZ"  # trailing 'Z' literal, UTC


def exid_emit(now: datetime | None = None) -> str:
    """Generate a new EXID in UTC."""
    dt = now if now is not None else datetime.now(timezone.utc)
    if dt.tzinfo is None:
        raise ValueError("datetime must be timezone-aware")
    dt_utc = dt.astimezone(timezone.utc)
    return dt_utc.strftime(EXID_FMT)


def exid_decode(exid: str, tz: str | None = None) -> datetime:
    """
    Decode an EXID string to a timezone-aware datetime.
    Returns UTC if tz is None, else converted to requested IANA tz.
    """
    if len(exid) != 13 or not exid.endswith("Z"):
        raise ValueError("EXID must be exactly 13 chars and end with 'Z' (YYMMDDHHMMSSZ)")
    dt_utc = datetime.strptime(exid, EXID_FMT).replace(tzinfo=timezone.utc)
    if tz is None:
        return dt_utc
    return dt_utc.astimezone(ZoneInfo(tz))


def main() -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    sp_emit = sub.add_parser("emit", help="Emit a new EXID (UTC)")
    sp_emit.add_argument("--at", help="Optional ISO datetime, interpreted as UTC (e.g. 2026-02-13T08:30:15)")

    sp_dec = sub.add_parser("decode", help="Decode an EXID")
    sp_dec.add_argument("exid")
    sp_dec.add_argument("--tz", help="IANA timezone, e.g. America/Los_Angeles")

    sp_upd = sub.add_parser("update-units", help="Replace EXPERIMENTID column in a units.tsv with a new EXID")
    sp_upd.add_argument("--units-tsv", required=True, help="Path to units.tsv file")

    args = p.parse_args()

    if args.cmd == "emit":
        if args.at:
            # Interpret provided timestamp as UTC unless it includes an offset.
            dt = datetime.fromisoformat(args.at)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            print(exid_emit(dt))
        else:
            print(exid_emit())
        return

    if args.cmd == "decode":
        dt = exid_decode(args.exid, tz=args.tz)
        # Print ISO-8601 with offset (or Z via UTC)
        if dt.tzinfo == timezone.utc:
            print(dt.strftime("%Y-%m-%dT%H:%M:%SZ"))
        else:
            print(dt.isoformat())
        return

    if args.cmd == "update-units":
        tsv_path = Path(args.units_tsv)
        if not tsv_path.is_file():
            raise SystemExit(f"ERROR: file not found: {tsv_path}")

        # Timestamped backup
        bak_stamp = datetime.now(timezone.utc).strftime("%y%m%d%H%M%SZ")
        bak_path = tsv_path.with_name(f"{tsv_path.name}.bak.{bak_stamp}")
        shutil.copy2(tsv_path, bak_path)

        # Read, replace EXPERIMENTID, write back
        with open(tsv_path, newline="") as f:
            reader = csv.DictReader(f, delimiter="\t")
            fieldnames = reader.fieldnames or []
            if "EXPERIMENTID" not in fieldnames:
                raise SystemExit("ERROR: units.tsv has no EXPERIMENTID column")
            rows = list(reader)

        new_exid = exid_emit()
        for row in rows:
            row["EXPERIMENTID"] = new_exid

        with open(tsv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

        print(f"Backup:  {bak_path}")
        print(f"EXID:    {new_exid}")
        print(f"Updated: {len(rows)} row(s) in {tsv_path}")
        return


if __name__ == "__main__":
    main()
