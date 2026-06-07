"""Order BWA-MEM2A Slurm partitions by current Spot price.

This helper is intentionally narrow: it only updates
``bwa_mem2a_aln_sort.partition`` when that config section explicitly requests
``partition_strategy: spot_price_runtime``.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence

import yaml


class SpotPartitionError(RuntimeError):
    """Raised when dynamic partition ordering cannot be completed."""


@dataclass(frozen=True)
class PartitionPrice:
    partition: str
    min_price: float
    avg_price: float
    instance_prices: tuple[tuple[str, float], ...]


CommandRunner = Callable[[Sequence[str]], str]


def _run_aws(args: Sequence[str]) -> str:
    proc = subprocess.run(args, check=False, text=True, capture_output=True)
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise SpotPartitionError(
            f"read-only AWS CLI command failed rc={proc.returncode}: {' '.join(args)}"
            + (f"\n{stderr}" if stderr else "")
        )
    return proc.stdout


def _aws_base(region: str, profile: str | None = None) -> list[str]:
    args = ["aws"]
    if profile:
        args.extend(["--profile", profile])
    args.extend(["ec2"])
    return args


def _json_from_aws(args: Sequence[str], *, runner: CommandRunner) -> Mapping[str, Any]:
    try:
        payload = json.loads(runner(args))
    except json.JSONDecodeError as exc:
        raise SpotPartitionError(f"AWS CLI returned non-JSON output: {' '.join(args)}") from exc
    if not isinstance(payload, dict):
        raise SpotPartitionError(f"AWS CLI returned a non-object JSON payload: {' '.join(args)}")
    return payload


def _spot_price(
    *,
    instance_type: str,
    region: str,
    availability_zone: str,
    profile: str | None,
    runner: CommandRunner,
) -> float:
    args = _aws_base(region, profile)
    args.extend(
        [
            "describe-spot-price-history",
            "--region",
            region,
            "--availability-zone",
            availability_zone,
            "--instance-types",
            instance_type,
            "--product-descriptions",
            "Linux/UNIX",
            "--max-results",
            "1",
            "--output",
            "json",
        ]
    )
    payload = _json_from_aws(args, runner=runner)
    history = payload.get("SpotPriceHistory") or []
    if not history:
        raise SpotPartitionError(
            f"no current Spot price returned for {instance_type} in {availability_zone}"
        )
    try:
        return float(history[0]["SpotPrice"])
    except (KeyError, TypeError, ValueError) as exc:
        raise SpotPartitionError(
            f"invalid Spot price payload for {instance_type} in {availability_zone}"
        ) from exc


def _validate_instance_specs(
    *,
    instance_types: Sequence[str],
    region: str,
    profile: str | None,
    runner: CommandRunner,
) -> None:
    args = _aws_base(region, profile)
    args.extend(
        [
            "describe-instance-types",
            "--region",
            region,
            "--instance-types",
            *instance_types,
            "--output",
            "json",
        ]
    )
    payload = _json_from_aws(args, runner=runner)
    returned = {
        str(item.get("InstanceType"))
        for item in payload.get("InstanceTypes", [])
        if item.get("InstanceType")
    }
    missing = sorted(set(instance_types).difference(returned))
    if missing:
        raise SpotPartitionError(
            "describe-instance-types did not return every configured instance type: "
            + ", ".join(missing)
        )


def _as_list(value: Any, *, name: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise SpotPartitionError(f"bwa_mem2a_aln_sort.{name} must be a non-empty list")
    result = [str(item).strip() for item in value if str(item).strip()]
    if len(result) != len(value):
        raise SpotPartitionError(f"bwa_mem2a_aln_sort.{name} contains an empty value")
    if len(set(result)) != len(result):
        raise SpotPartitionError(f"bwa_mem2a_aln_sort.{name} contains duplicate values")
    return result


def _price_partitions(
    *,
    section: Mapping[str, Any],
    runner: CommandRunner,
) -> list[PartitionPrice]:
    region = str(section.get("spot_price_region") or "").strip()
    availability_zone = str(section.get("spot_price_availability_zone") or "").strip()
    profile = str(section.get("spot_price_profile") or "").strip() or None
    if not region:
        raise SpotPartitionError("bwa_mem2a_aln_sort.spot_price_region is required")
    if not availability_zone:
        raise SpotPartitionError("bwa_mem2a_aln_sort.spot_price_availability_zone is required")

    allowed = _as_list(section.get("allowed_partitions"), name="allowed_partitions")
    catalog = section.get("partition_instance_catalog")
    if not isinstance(catalog, dict) or not catalog:
        raise SpotPartitionError(
            "bwa_mem2a_aln_sort.partition_instance_catalog must be a non-empty mapping"
        )

    all_instance_types: list[str] = []
    for partition in allowed:
        instance_types = _as_list(
            catalog.get(partition),
            name=f"partition_instance_catalog.{partition}",
        )
        all_instance_types.extend(instance_types)
    _validate_instance_specs(
        instance_types=sorted(set(all_instance_types)),
        region=region,
        profile=profile,
        runner=runner,
    )

    prices: list[PartitionPrice] = []
    for partition in allowed:
        instance_prices = tuple(
            (instance_type, _spot_price(
                instance_type=instance_type,
                region=region,
                availability_zone=availability_zone,
                profile=profile,
                runner=runner,
            ))
            for instance_type in catalog[partition]
        )
        numeric_prices = [price for _, price in instance_prices]
        prices.append(
            PartitionPrice(
                partition=partition,
                min_price=min(numeric_prices),
                avg_price=statistics.fmean(numeric_prices),
                instance_prices=instance_prices,
            )
        )
    return prices


def order_bwa_partitions(
    rule_config: Mapping[str, Any],
    *,
    runner: CommandRunner = _run_aws,
) -> tuple[str | None, list[PartitionPrice]]:
    """Return the ordered partition string for BWA-MEM2A, if dynamic mode is enabled."""
    section = rule_config.get("bwa_mem2a_aln_sort")
    if not isinstance(section, dict):
        raise SpotPartitionError("rule_config lacks bwa_mem2a_aln_sort mapping")
    strategy = str(section.get("partition_strategy") or "").strip()
    if not strategy:
        return None, []
    if strategy != "spot_price_runtime":
        raise SpotPartitionError(
            "unsupported bwa_mem2a_aln_sort.partition_strategy: " + strategy
        )
    prices = _price_partitions(section=section, runner=runner)
    ordered = sorted(prices, key=lambda item: (item.avg_price, item.min_price, item.partition))
    return ",".join(item.partition for item in ordered), ordered


def update_rule_config(
    path: Path,
    *,
    runner: CommandRunner = _run_aws,
    dry_run: bool = False,
) -> tuple[str | None, list[PartitionPrice]]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise SpotPartitionError(f"rule config must be a mapping: {path}")
    ordered_partition, prices = order_bwa_partitions(data, runner=runner)
    if ordered_partition is None:
        return None, []
    section = data["bwa_mem2a_aln_sort"]
    old_partition = str(section.get("partition") or "")
    if old_partition != ordered_partition and not dry_run:
        text = path.read_text(encoding="utf-8")
        path.write_text(_replace_bwa_partition_line(text, ordered_partition), encoding="utf-8")
    return ordered_partition, prices


def _replace_bwa_partition_line(text: str, ordered_partition: str) -> str:
    """Replace only the BWA partition line, preserving the rest of the YAML text."""
    lines = text.splitlines(keepends=True)
    section_indent: int | None = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if stripped == "bwa_mem2a_aln_sort:":
            section_indent = indent
            continue
        if section_indent is None:
            continue
        if indent <= section_indent and stripped.endswith(":"):
            break
        if indent > section_indent and stripped.startswith("partition:"):
            newline = "\n" if line.endswith("\n") else ""
            prefix = line[:indent]
            lines[index] = f"{prefix}partition: {ordered_partition}{newline}"
            return "".join(lines)
    raise SpotPartitionError("could not locate bwa_mem2a_aln_sort.partition in rule config")


def _format_prices(prices: Iterable[PartitionPrice]) -> str:
    lines = []
    for item in prices:
        instances = ",".join(f"{itype}={price:.6f}" for itype, price in item.instance_prices)
        lines.append(
            f"{item.partition}: avg={item.avg_price:.6f} min={item.min_price:.6f} {instances}"
        )
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rule-config", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        ordered, prices = update_rule_config(args.rule_config, dry_run=args.dry_run)
    except SpotPartitionError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if ordered is None:
        print("bwa_mem2a_aln_sort dynamic partition ordering disabled", file=sys.stderr)
        return 0
    print(f"bwa_mem2a_aln_sort.partition={ordered}", file=sys.stderr)
    print(_format_prices(prices), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
