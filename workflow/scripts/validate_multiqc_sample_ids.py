#!/usr/bin/env python3
"""Validate DayOA MultiQC sample IDs against the staged input manifest."""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


MODULE_ALIASES = {
    "bcftools_stats": ("multiqc_bcftools_stats", "multiqc_bcftools_stats_1"),
    "fastqc": ("multiqc_fastqc", "multiqc_fastqc_1"),
    "mosdepth": ("mosdepth_cov_dist", "mosdepth_cumcov_dist", "mosdepth_perchrom"),
    "peddy": ("multiqc_peddy",),
    "samtools_flagstat": ("multiqc_samtools_flagstat",),
    "samtools_idxstats": ("multiqc_samtools_idxstats",),
    "samtools_stats": ("multiqc_samtools_stats",),
    "somalier": ("multiqc_somalier",),
    "verifybamid": ("multiqc_verifybamid",),
}


def read_manifest(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not rows:
        raise ValueError(f"empty MultiQC staging manifest: {path}")
    for row in rows:
        sample = row.get("Sample", "")
        module = row.get("module", "")
        if not sample or not module:
            raise ValueError(f"manifest row missing Sample/module: {row}")
    return rows


def collect_raw_samples(multiqc_data: Path) -> dict[str, set[str]]:
    payload = json.loads(multiqc_data.read_text(encoding="utf-8"))
    raw = payload.get("report_saved_raw_data")
    if not isinstance(raw, dict):
        raise ValueError(f"MultiQC data lacks report_saved_raw_data: {multiqc_data}")
    observed: dict[str, set[str]] = defaultdict(set)
    for key, value in raw.items():
        if isinstance(value, dict):
            observed[key].update(str(sample) for sample in value.keys())
    return observed


def expected_by_module(rows: list[dict[str, str]]) -> dict[str, set[str]]:
    expected: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        module = row["module"]
        sample = row["Sample"]
        if module in MODULE_ALIASES:
            expected[module].add(sample)
    return expected


def stage_depth(sample: str) -> int:
    return len([part for part in sample.split(".") if part])


def base_sample(sample: str) -> str:
    return sample.split(".", 1)[0]


def validate(manifest: Path, multiqc_data: Path) -> None:
    rows = read_manifest(manifest)
    observed = collect_raw_samples(multiqc_data)
    expected = expected_by_module(rows)
    failures: list[str] = []
    for module, samples in sorted(expected.items()):
        aliases = MODULE_ALIASES[module]
        present = set()
        for alias in aliases:
            present.update(observed.get(alias, set()))
        if not present:
            continue
        expected_bases = {base_sample(sample) for sample in samples if stage_depth(sample) > 1}
        collapsed = sorted(sample for sample in present if sample in expected_bases)
        if collapsed:
            failures.append(
                f"{module} collapsed stage-aware samples to base IDs: {', '.join(collapsed)}"
            )
        missing = sorted(sample for sample in samples if sample not in present)
        if missing:
            failures.append(
                f"{module} missing staged sample IDs: {', '.join(missing[:20])}"
            )
    if failures:
        raise SystemExit("ERROR: MultiQC sample identity validation failed\n" + "\n".join(failures))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--multiqc-data", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    validate(Path(args.manifest), Path(args.multiqc_data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
