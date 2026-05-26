#!/usr/bin/env python3
"""Snakemake wrapper for DayOA Dewey/QEO artifact registration."""

from __future__ import annotations

from daylily_omics_analysis.qeo_registration import main


if __name__ == "__main__":
    raise SystemExit(main())

