#!/usr/bin/env python3
"""Run pycoQC with a compatibility patch for read-only pandas arrays."""

from __future__ import annotations

import argparse
import numpy as np

from pycoQC.pycoQC import pycoQC
from pycoQC.pycoQC_plot import pycoQC_plot


def _compute_n50_mutable(data):
    values = np.array(data.dropna().values, copy=True)
    values.sort()
    half_sum = values.sum() / 2
    cum_sum = 0
    for value in values:
        cum_sum += value
        if cum_sum >= half_sum:
            return int(value)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run pycoQC while avoiding read-only array sort failures."
    )
    parser.add_argument(
        "-f",
        "--summary-file",
        nargs="+",
        required=True,
        help="One or more ONT sequencing_summary files.",
    )
    parser.add_argument("-o", "--html-outfile", required=True)
    parser.add_argument("-j", "--json-outfile", required=True)
    parser.add_argument("--report-title", default="PycoQC report")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    pycoQC_plot._compute_N50 = staticmethod(_compute_n50_mutable)
    pycoQC(
        summary_file=args.summary_file,
        html_outfile=args.html_outfile,
        json_outfile=args.json_outfile,
        report_title=args.report_title,
    )


if __name__ == "__main__":
    main()
