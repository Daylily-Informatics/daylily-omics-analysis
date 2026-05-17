#!/usr/bin/env python3
"""Render MultiQC module exclusions from a one-module-per-line file."""

from __future__ import annotations

import argparse
import re
import shlex
from pathlib import Path


MODULE_RE = re.compile(r"^[A-Za-z0-9_.:/-]+$")


def render_args(path: Path) -> str:
    args: list[str] = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        module = raw.strip()
        if not module:
            continue
        if module != raw or not MODULE_RE.fullmatch(module):
            raise ValueError(
                f"invalid MultiQC module name in {path} line {lineno}: {raw!r}"
            )
        args.extend(["--exclude", module])
    return " ".join(shlex.quote(arg) for arg in args)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exclude_file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(render_args(Path(args.exclude_file)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
