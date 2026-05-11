#!/usr/bin/env python3
"""Build a strict MultiQC intro_text YAML fragment from benchmark data."""

from __future__ import annotations

import argparse
import csv
import html
import re
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Mapping, Sequence


REQUIRED_BENCHMARK_COLUMNS = {
    "task_cost",
    "rule",
    "combined_rule",
    "rule_prefix",
}

CATEGORY_ALIGNER = "aligner"
CATEGORY_DEDUPER = "deduper"
CATEGORY_SNV_CALLER = "snv_caller"
CATEGORY_OTHER = "other"
CATEGORY_ORDER = (
    CATEGORY_ALIGNER,
    CATEGORY_DEDUPER,
    CATEGORY_SNV_CALLER,
    CATEGORY_OTHER,
)

ALIGNER_TOKENS = frozenset(
    {
        "align",
        "aln",
        "alnsort",
        "bwa2a",
        "bwa2af",
        "hisat2",
    }
)
DEDUPER_TOKENS = frozenset(
    {
        "dedup",
        "dmd",
        "dppl",
        "markdup",
        "mrkdup",
        "smd",
    }
)
SNV_CALLER_TOKENS = frozenset(
    {
        "bcftools",
        "cgt7p",
        "clair3",
        "deep15",
        "deep19",
        "deep19b",
        "deep19r",
        "deepug",
        "dvsom",
        "freebayes",
        "gatk",
        "lfq2",
        "lofreq",
        "mutect2",
        "oct",
        "rochehc",
        "sentd",
        "sentdhiom",
        "sentdhiomr",
        "sentdhipm",
        "sentdhipmr",
        "sentdhrom",
        "sentdhup",
        "sentdhupm",
        "sentdhupmr",
        "sentdont",
        "sentdpb",
        "sentdug",
        "strelka",
    }
)
SNV_CALLER_ACTION_TOKENS = frozenset(
    {
        "concat",
        "fofn",
        "gvcf",
        "index",
        "merge",
        "sort",
        "vcf",
    }
)

TOKEN_RE = re.compile(r"[A-Za-z0-9]+")
CHROMOSOME_RANGE_RE = re.compile(r"^(?:chr)?[0-9xyXYM]+(?:-[0-9xyXYM]+)?$")
MONEY_QUANT = Decimal("0.01")


@dataclass(frozen=True)
class CostSummary:
    sample_count: int
    task_count: int
    total_task_cost: Decimal
    per_sample_task_cost: Decimal
    category_task_costs: Mapping[str, Decimal]
    category_per_sample_costs: Mapping[str, Decimal]


def _tokens(value: str) -> tuple[str, ...]:
    return tuple(match.group(0).lower() for match in TOKEN_RE.finditer(value))


def _rule_suffix(row: Mapping[str, str]) -> str:
    rule = row["rule"].strip()
    prefix = row["rule_prefix"].strip()
    if not rule:
        raise ValueError("Benchmark row has an empty rule value.")
    if not prefix:
        raise ValueError(f"Benchmark rule {rule!r} has an empty rule_prefix value.")
    if rule == prefix:
        return ""
    expected_prefix = f"{prefix}."
    if not rule.startswith(expected_prefix):
        raise ValueError(
            f"Benchmark rule {rule!r} does not match rule_prefix {prefix!r}."
        )
    return rule[len(expected_prefix) :]


def _rule_action(row: Mapping[str, str]) -> str:
    suffix = _rule_suffix(row)
    if not suffix:
        return row["rule"].strip()
    return suffix.rsplit(".", maxsplit=1)[-1].strip()


def _has_snv_caller(row: Mapping[str, str]) -> bool:
    return any(token in SNV_CALLER_TOKENS for token in _tokens(_rule_suffix(row)))


def classify_rule(row: Mapping[str, str]) -> str:
    """Return the deterministic cost bucket for a benchmark row."""

    action = _rule_action(row).lower()
    action_tokens = _tokens(action)
    if any(token in ALIGNER_TOKENS for token in action_tokens):
        return CATEGORY_ALIGNER
    if any(token in DEDUPER_TOKENS for token in action_tokens):
        return CATEGORY_DEDUPER
    if _has_snv_caller(row) and (
        any(token in SNV_CALLER_ACTION_TOKENS for token in action_tokens)
        or CHROMOSOME_RANGE_RE.match(action) is not None
        or action in SNV_CALLER_TOKENS
    ):
        return CATEGORY_SNV_CALLER
    return CATEGORY_OTHER


def _read_tsv_rows(path: Path, label: str) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames is None:
            raise ValueError(f"{label} is empty: {path}")
        rows: list[dict[str, str]] = []
        for line_number, row in enumerate(reader, start=2):
            if None in row:
                raise ValueError(f"{label} row {line_number} has extra columns: {path}")
            if any((value or "").strip() for value in row.values()):
                rows.append({key: value for key, value in row.items()})
    return rows


def _validate_benchmark_columns(path: Path, fieldnames: Sequence[str] | None) -> None:
    found = set(fieldnames or [])
    missing = sorted(REQUIRED_BENCHMARK_COLUMNS - found)
    if missing:
        joined = ", ".join(missing)
        raise ValueError(f"Benchmark TSV is missing required columns: {joined}: {path}")


def _parse_task_cost(value: str, path: Path, line_number: int) -> Decimal:
    raw = value.strip()
    if not raw:
        raise ValueError(f"Benchmark row {line_number} has empty task_cost: {path}")
    try:
        cost = Decimal(raw)
    except InvalidOperation as exc:
        raise ValueError(
            f"Benchmark row {line_number} has invalid task_cost {raw!r}: {path}"
        ) from exc
    if not cost.is_finite() or cost < 0:
        raise ValueError(f"Benchmark row {line_number} has invalid task_cost {raw!r}: {path}")
    return cost


def _read_benchmark_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        _validate_benchmark_columns(path, reader.fieldnames)
        rows: list[dict[str, str]] = []
        for line_number, row in enumerate(reader, start=2):
            if None in row:
                raise ValueError(f"Benchmark row {line_number} has extra columns: {path}")
            if not any((value or "").strip() for value in row.values()):
                continue
            normalized = {key: value for key, value in row.items()}
            for column in ("rule", "combined_rule", "rule_prefix"):
                if not normalized[column].strip():
                    raise ValueError(
                        f"Benchmark row {line_number} has empty {column}: {path}"
                    )
            _parse_task_cost(normalized["task_cost"], path, line_number)
            rows.append(normalized)
    if not rows:
        raise ValueError(f"Benchmark TSV contains zero data rows: {path}")
    return rows


def read_sample_count(samples_tsv: str | Path) -> int:
    path = Path(samples_tsv)
    sample_count = len(_read_tsv_rows(path, "samples.tsv"))
    if sample_count == 0:
        raise ValueError(f"samples.tsv contains zero samples: {path}")
    return sample_count


def summarize_costs(benchmark_tsv: str | Path, samples_tsv: str | Path) -> CostSummary:
    benchmark_path = Path(benchmark_tsv)
    sample_count = read_sample_count(samples_tsv)
    category_costs = {category: Decimal("0") for category in CATEGORY_ORDER}
    total = Decimal("0")
    task_count = 0

    for line_offset, row in enumerate(_read_benchmark_rows(benchmark_path), start=2):
        cost = _parse_task_cost(row["task_cost"], benchmark_path, line_offset)
        total += cost
        task_count += 1
        category_costs[classify_rule(row)] += cost

    divisor = Decimal(sample_count)
    return CostSummary(
        sample_count=sample_count,
        task_count=task_count,
        total_task_cost=total,
        per_sample_task_cost=total / divisor,
        category_task_costs=category_costs,
        category_per_sample_costs={
            category: cost / divisor for category, cost in category_costs.items()
        },
    )


def _money(value: Decimal) -> str:
    quantized = value.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)
    return f"${quantized:,.2f}"


def build_intro_text(summary: CostSummary, multiqc_command: str) -> str:
    command = multiqc_command.strip()
    if not command:
        raise ValueError("MultiQC command string is required.")

    escaped_command = html.escape(command, quote=True)
    return "\n".join(
        [
            "<details>",
            "  <summary>Daylily final report guide and cost summary</summary>",
            "  <p>This report summarizes the Daylily WGS run from raw-read QC through alignment, coverage, sample identity, small-variant QC, contamination checks, control concordance, annotation, repeat-expansion calls, task benchmarks, and software versions.</p>",
            "  <p>FastQC covers raw-read quality; Samtools, Mosdepth, goleft, Alignstats, and norm coverage evenness cover mapping and coverage; Peddy and Somalier cover sample identity and relationship checks; BCFtools and concordance tables cover variant QC against controls; VerifyBamID2, GATK, and site-mix tables cover contamination; VEP and ExpansionHunter summarize annotation and STR outputs.</p>",
            "  <table>",
            "    <thead><tr><th>Metric</th><th>Value</th></tr></thead>",
            "    <tbody>",
            f"      <tr><td>Samples</td><td>{summary.sample_count}</td></tr>",
            f"      <tr><td>Benchmark tasks</td><td>{summary.task_count}</td></tr>",
            (
                "      <tr><td>Total benchmark task_cost</td><td>"
                f"{_money(summary.total_task_cost)}</td></tr>"
            ),
            (
                "      <tr><td>Per-sample benchmark task_cost</td><td>"
                f"{_money(summary.per_sample_task_cost)}</td></tr>"
            ),
            (
                "      <tr><td>Avg per-sample aligner task_cost</td><td>"
                f"{_money(summary.category_per_sample_costs[CATEGORY_ALIGNER])}</td></tr>"
            ),
            (
                "      <tr><td>Avg per-sample deduper task_cost</td><td>"
                f"{_money(summary.category_per_sample_costs[CATEGORY_DEDUPER])}</td></tr>"
            ),
            (
                "      <tr><td>Avg per-sample SNV caller task_cost</td><td>"
                f"{_money(summary.category_per_sample_costs[CATEGORY_SNV_CALLER])}</td></tr>"
            ),
            "    </tbody>",
            "  </table>",
            "  <p><strong>MultiQC command</strong></p>",
            f"  <pre><code>{escaped_command}</code></pre>",
            "</details>",
        ]
    )


def build_intro_yaml(
    benchmark_tsv: str | Path,
    samples_tsv: str | Path,
    multiqc_command: str,
) -> str:
    summary = summarize_costs(benchmark_tsv, samples_tsv)
    intro_text = build_intro_text(summary, multiqc_command)
    yaml_lines = ["intro_text: |-"]
    yaml_lines.extend(f"  {line}" if line else "  " for line in intro_text.splitlines())
    return "\n".join(yaml_lines) + "\n"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark-tsv", required=True, type=Path)
    parser.add_argument("--samples-tsv", required=True, type=Path)
    parser.add_argument("--multiqc-command", required=True)
    parser.add_argument("--output", "-o", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    yaml_text = build_intro_yaml(
        args.benchmark_tsv,
        args.samples_tsv,
        args.multiqc_command,
    )
    if args.output is None:
        sys.stdout.write(yaml_text)
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(yaml_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
