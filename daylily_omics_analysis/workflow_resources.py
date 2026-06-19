"""Shared Snakemake resource helpers for DayOA workflows."""

from __future__ import annotations

import math
import os
from pathlib import Path
from typing import Any, Mapping


class ResourceConfigError(RuntimeError):
    """Raised when dynamic resource configuration is invalid."""


def _bool_config(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def _positive_int(section: Mapping[str, Any], key: str) -> int:
    try:
        value = int(section[key])
    except (KeyError, TypeError, ValueError) as exc:
        raise ResourceConfigError(f"doppelmark.{key} must be a positive integer") from exc
    if value <= 0:
        raise ResourceConfigError(f"doppelmark.{key} must be a positive integer")
    return value


def derive_doppelmark_mem_mb(
    input_bam: str | os.PathLike[str],
    section: Mapping[str, Any],
    *,
    day_profile: str | None = None,
) -> int:
    """Calculate DPPL/Doppelmark memory from input BAM size for Slurm runs."""
    profile = day_profile if day_profile is not None else os.environ.get("DAY_PROFILE")
    configured = _positive_int(section, "mem_mb")
    if profile != "slurm" or not _bool_config(section.get("dynamic_mem_mb")):
        return configured

    path = Path(input_bam)
    try:
        bam_size_bytes = path.stat().st_size
    except FileNotFoundError as exc:
        raise FileNotFoundError(f"doppelmark input BAM is not readable: {path}") from exc
    except OSError as exc:
        raise ResourceConfigError(f"doppelmark input BAM is not readable: {path}") from exc
    if bam_size_bytes <= 0:
        raise ResourceConfigError(f"doppelmark input BAM is empty: {path}")

    floor_mb = _positive_int(section, "dynamic_mem_floor_mb")
    per_gib_mb = _positive_int(section, "dynamic_mem_per_gib_mb")
    cap_mb = _positive_int(section, "dynamic_mem_cap_mb")
    round_mb = _positive_int(section, "dynamic_mem_round_mb")
    if floor_mb > cap_mb:
        raise ResourceConfigError("doppelmark.dynamic_mem_floor_mb must be <= dynamic_mem_cap_mb")

    bam_size_gib = bam_size_bytes / float(1024**3)
    calculated = max(floor_mb, math.ceil(bam_size_gib * per_gib_mb))
    rounded = int(math.ceil(calculated / float(round_mb)) * round_mb)
    return min(rounded, cap_mb)
