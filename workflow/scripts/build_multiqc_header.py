#!/usr/bin/env python3
"""Build a strict MultiQC header YAML document."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_multiqc_intro import build_intro_text, summarize_costs  # noqa: E402


class LiteralString(str):
    """Marker for YAML multiline literal scalars."""


class HeaderDumper(yaml.SafeDumper):
    """YAML dumper that preserves the HTML intro as a block scalar."""


def _literal_string_representer(
    dumper: yaml.SafeDumper, data: LiteralString
) -> yaml.ScalarNode:
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")


HeaderDumper.add_representer(LiteralString, _literal_string_representer)


def build_header_yaml(
    *,
    benchmark_tsv: str | Path,
    samples_tsv: str | Path,
    multiqc_command: str,
    project_budget: str,
    budget_runtime: str,
    spot_instances: str,
    spot_costs: str,
    aligner_costs: str,
    mrkdup_cost: str,
    results_size: str,
) -> str:
    summary = summarize_costs(benchmark_tsv, samples_tsv)
    intro_text = build_intro_text(summary, multiqc_command)
    document = {
        "report_header_info": [
            {"Project/Budget": project_budget},
            {"Budget @ Runtime": budget_runtime},
            {"Spot Instances": spot_instances},
            {"Spot Costs per hr": spot_costs},
            {"FQ->BAM.sort avg Costs": aligner_costs},
            {"BAM mrkdup avg Cost": mrkdup_cost},
            {"Results Dir (GB)": results_size},
        ],
        "intro_text": LiteralString(intro_text),
    }
    return yaml.dump(document, Dumper=HeaderDumper, sort_keys=False, width=120)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark-tsv", required=True, type=Path)
    parser.add_argument("--samples-tsv", required=True, type=Path)
    parser.add_argument("--multiqc-command", required=True)
    parser.add_argument("--project-budget", required=True)
    parser.add_argument("--budget-runtime", required=True)
    parser.add_argument("--spot-instances", required=True)
    parser.add_argument("--spot-costs", required=True)
    parser.add_argument("--aligner-costs", required=True)
    parser.add_argument("--mrkdup-cost", required=True)
    parser.add_argument("--results-size", required=True)
    parser.add_argument("--output", "-o", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    yaml_text = build_header_yaml(
        benchmark_tsv=args.benchmark_tsv,
        samples_tsv=args.samples_tsv,
        multiqc_command=args.multiqc_command,
        project_budget=args.project_budget,
        budget_runtime=args.budget_runtime,
        spot_instances=args.spot_instances,
        spot_costs=args.spot_costs,
        aligner_costs=args.aligner_costs,
        mrkdup_cost=args.mrkdup_cost,
        results_size=args.results_size,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(yaml_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
