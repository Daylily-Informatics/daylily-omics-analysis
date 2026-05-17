#!/usr/bin/env python3
"""Keep DayOA operational logs out of MultiQC custom-content discovery."""

from __future__ import annotations

import argparse
from pathlib import Path


def guard_log_dir(log_dir: Path) -> list[Path]:
    renamed: list[Path] = []
    if not log_dir.exists():
        return renamed

    bad_logs = sorted(path for path in log_dir.glob("*_mqc.log") if path.stat().st_size)
    if bad_logs:
        joined = "\n".join(str(path) for path in bad_logs)
        raise SystemExit(
            "ERROR: non-empty *_mqc.log files are not valid DayOA MultiQC inputs. "
            "Convert reportable metrics to *_mqc.tsv or *_mqc.csv and keep logs "
            f"out of other_reports/logs:\n{joined}"
        )

    for path in sorted(log_dir.glob("*_mqc.log")):
        target = path.with_name(path.name.removesuffix("_mqc.log") + "_legacy_custom_data.log")
        path.rename(target)
        renamed.append(target)
    return renamed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log-dir", required=True, type=Path)
    args = parser.parse_args()

    renamed = guard_log_dir(args.log_dir)
    for path in renamed:
        print(f"renamed_zero_byte_mqc_log\t{path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
