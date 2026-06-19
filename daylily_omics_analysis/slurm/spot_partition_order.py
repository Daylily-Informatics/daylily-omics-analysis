"""Order Slurm partitions by live AWS Spot cost per vCPU.

The workflow calls :func:`derive_partition_order` from Snakemake resource
expressions. The function preserves local execution behavior, but Slurm
execution requires live Slurm node metadata and read-only AWS EC2 pricing
permissions. Missing metadata fails hard instead of falling back to static
partition catalogs.
"""

from __future__ import annotations

import csv
import fcntl
import ipaddress
import json
import os
import statistics
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence


class SpotPartitionError(RuntimeError):
    """Raised when dynamic partition ordering cannot be completed."""


CommandRunner = Callable[[Sequence[str]], str]

PARTITION_COST_LOG = Path.home() / ".config/dayoa/partition_costs.log"
CACHE_TTL_SECONDS = 1800
CACHE_HEADER = (
    "created_at_epoch",
    "created_at_iso",
    "region",
    "availability_zone",
    "partition",
    "median_usd_per_vcpu_hr",
    "instance_types",
    "price_samples_json",
)

PARALLELCLUSTER_FLEET_CONFIG = Path("/etc/parallelcluster/slurm_plugin/fleet-config.json")


@dataclass(frozen=True)
class PartitionCost:
    partition: str
    median_usd_per_vcpu_hr: float
    instance_types: tuple[str, ...]
    price_samples: tuple[tuple[str, float], ...]
    created_at_epoch: float
    created_at_iso: str
    region: str
    availability_zone: str


def _run_command(args: Sequence[str]) -> str:
    proc = subprocess.run(args, check=False, text=True, capture_output=True)
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise SpotPartitionError(
            f"read-only command failed rc={proc.returncode}: {' '.join(args)}"
            + (f"\n{stderr}" if stderr else "")
        )
    return proc.stdout


def _split_partition_csv(partition_csv: str) -> list[str]:
    parts = [part.strip() for part in str(partition_csv or "").split(",") if part.strip()]
    if not parts:
        raise SpotPartitionError("resources.partition must be a non-empty CSV string")
    if len(set(parts)) != len(parts):
        raise SpotPartitionError(f"resources.partition contains duplicates: {partition_csv!r}")
    return parts


def _json_from_command(args: Sequence[str], *, runner: CommandRunner) -> Mapping[str, object]:
    try:
        payload = json.loads(runner(args))
    except json.JSONDecodeError as exc:
        raise SpotPartitionError(f"command returned non-JSON output: {' '.join(args)}") from exc
    if not isinstance(payload, dict):
        raise SpotPartitionError(f"command returned a non-object JSON payload: {' '.join(args)}")
    return payload


def _env_region(env: Mapping[str, str]) -> str:
    region = (
        env.get("AWS_REGION")
        or env.get("AWS_DEFAULT_REGION")
        or env.get("DAY_AWS_REGION")
        or env.get("AWS_DEFAULT_REGION_NAME")
        or ""
    ).strip()
    if not region:
        raise SpotPartitionError(
            "AWS region is required for partition price ordering; set AWS_REGION or AWS_DEFAULT_REGION"
        )
    return region


def _aws_base(region: str, profile: str | None, service: str = "ec2") -> list[str]:
    args = ["aws"]
    if profile:
        args.extend(["--profile", profile])
    args.extend([service, "--region", region])
    return args


def _parse_key_values(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for token in str(text).split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        values[key] = value
    return values


def _nodes_for_partition(partition: str, *, runner: CommandRunner) -> list[str]:
    output = runner(["sinfo", "-h", "-p", partition, "-N", "-o", "%N"])
    nodes = [line.strip() for line in output.splitlines() if line.strip()]
    if not nodes:
        raise SpotPartitionError(f"sinfo returned no nodes for partition {partition!r}")
    return sorted(set(nodes))


def _node_metadata(
    node_names: Sequence[str],
    *,
    runner: CommandRunner,
) -> dict[str, dict[str, str]]:
    metadata: dict[str, dict[str, str]] = {}
    for node_name in node_names:
        values = _parse_key_values(runner(["scontrol", "show", "node", "-o", node_name]))
        if not values:
            raise SpotPartitionError(f"scontrol returned no metadata for node {node_name!r}")
        metadata[node_name] = values
    return metadata


def _instance_ids_from_address_filter(
    filter_name: str,
    values: Sequence[str],
    *,
    region: str,
    profile: str | None,
    runner: CommandRunner,
) -> list[str]:
    if not values:
        return []
    args = _aws_base(region, profile)
    args.extend(
        [
            "describe-instances",
            "--filters",
            f"Name={filter_name},Values=" + ",".join(sorted(set(values))),
            "--output",
            "json",
        ]
    )
    payload = _json_from_command(args, runner=runner)
    ids: list[str] = []
    for reservation in payload.get("Reservations", []):
        if not isinstance(reservation, dict):
            continue
        for instance in reservation.get("Instances", []):
            if isinstance(instance, dict) and instance.get("InstanceId"):
                ids.append(str(instance["InstanceId"]))
    return ids


def _node_instance_ids(
    node_metadata: Mapping[str, Mapping[str, str]],
    *,
    region: str,
    profile: str | None,
    runner: CommandRunner,
) -> list[str]:
    instance_ids: list[str] = []
    private_ips: list[str] = []
    private_dns_names: list[str] = []
    for node_name, values in node_metadata.items():
        instance_id = values.get("InstanceId") or values.get("InstanceID")
        if instance_id:
            instance_ids.append(instance_id)
            continue
        node_addr = values.get("NodeAddr") or values.get("NodeHostName")
        if node_addr:
            try:
                ipaddress.ip_address(node_addr)
            except ValueError:
                private_dns_names.append(node_addr)
            else:
                private_ips.append(node_addr)

    if instance_ids:
        return sorted(set(instance_ids))
    if not private_ips and not private_dns_names:
        return []

    ids = []
    ids.extend(
        _instance_ids_from_address_filter(
            "private-ip-address",
            private_ips,
            region=region,
            profile=profile,
            runner=runner,
        )
    )
    ids.extend(
        _instance_ids_from_address_filter(
            "private-dns-name",
            private_dns_names,
            region=region,
            profile=profile,
            runner=runner,
        )
    )
    return sorted(set(ids))


def _parallelcluster_fleet_payload() -> Mapping[str, object]:
    try:
        payload = json.loads(PARALLELCLUSTER_FLEET_CONFIG.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SpotPartitionError(
            "Slurm nodes did not resolve to EC2 instances and ParallelCluster fleet "
            f"config is missing: {PARALLELCLUSTER_FLEET_CONFIG}"
        ) from exc
    except json.JSONDecodeError as exc:
        raise SpotPartitionError(
            f"ParallelCluster fleet config is not valid JSON: {PARALLELCLUSTER_FLEET_CONFIG}"
        ) from exc
    if not isinstance(payload, dict):
        raise SpotPartitionError(
            f"ParallelCluster fleet config is not a JSON object: {PARALLELCLUSTER_FLEET_CONFIG}"
        )
    return payload


def _node_feature_resources(
    partition: str,
    node_metadata: Mapping[str, Mapping[str, str]],
    resource_names: set[str],
) -> set[str]:
    resources: set[str] = set()
    unmapped: list[str] = []
    ambiguous: list[str] = []
    for node_name, values in node_metadata.items():
        if partition not in str(values.get("Partitions") or "").split(","):
            continue
        feature_csv = (
            values.get("AvailableFeatures")
            or values.get("ActiveFeatures")
            or values.get("Feature")
            or ""
        )
        node_features = {feature.strip() for feature in feature_csv.split(",") if feature.strip()}
        matches = sorted(node_features.intersection(resource_names))
        if len(matches) == 1:
            resources.add(matches[0])
        elif matches:
            ambiguous.append(f"{node_name}={','.join(matches)}")
        else:
            unmapped.append(f"{node_name}={feature_csv or '<empty>'}")
    if ambiguous:
        raise SpotPartitionError(
            f"ParallelCluster node features map to multiple resources for {partition!r}: "
            + "; ".join(ambiguous)
        )
    if unmapped:
        raise SpotPartitionError(
            f"ParallelCluster node features did not map to fleet resources for {partition!r}: "
            + "; ".join(unmapped)
        )
    return resources


def _parallelcluster_instance_metadata(
    partition: str,
    node_metadata: Mapping[str, Mapping[str, str]],
    *,
    region: str,
    profile: str | None,
    runner: CommandRunner,
) -> dict[str, tuple[str, str]]:
    payload = _parallelcluster_fleet_payload()
    queue_payload = payload.get(partition)
    if not isinstance(queue_payload, dict):
        raise SpotPartitionError(
            f"ParallelCluster fleet config has no queue for Slurm partition {partition!r}"
        )

    resource_names = {str(name) for name in queue_payload}
    resources = _node_feature_resources(partition, node_metadata, resource_names)
    if not resources:
        raise SpotPartitionError(
            f"Slurm node metadata did not expose ParallelCluster resources for {partition!r}"
        )

    subnet_ids: set[str] = set()
    instance_types: set[str] = set()
    for resource in sorted(resources):
        resource_payload = queue_payload.get(resource)
        if not isinstance(resource_payload, dict):
            raise SpotPartitionError(
                f"ParallelCluster fleet config resource is malformed: {partition}/{resource}"
            )
        networking = resource_payload.get("Networking")
        if not isinstance(networking, dict):
            raise SpotPartitionError(
                f"ParallelCluster fleet config resource has no Networking block: "
                f"{partition}/{resource}"
            )
        subnets = networking.get("SubnetIds")
        if not isinstance(subnets, list) or not all(isinstance(item, str) for item in subnets):
            raise SpotPartitionError(
                f"ParallelCluster fleet config resource has malformed SubnetIds: "
                f"{partition}/{resource}"
            )
        subnet_ids.update(subnets)

        instances = resource_payload.get("Instances")
        if not isinstance(instances, list) or not instances:
            raise SpotPartitionError(
                f"ParallelCluster fleet config resource has no Instances: {partition}/{resource}"
            )
        for instance in instances:
            if not isinstance(instance, dict):
                raise SpotPartitionError(
                    f"ParallelCluster fleet config has malformed instance entry: "
                    f"{partition}/{resource}"
                )
            instance_type = str(instance.get("InstanceType") or "").strip()
            if not instance_type:
                raise SpotPartitionError(
                    f"ParallelCluster fleet config instance entry has no InstanceType: "
                    f"{partition}/{resource}"
                )
            instance_types.add(instance_type)

    if not subnet_ids:
        raise SpotPartitionError(
            f"ParallelCluster fleet config has no configured subnets for {partition!r}"
        )
    if len(subnet_ids) != 1:
        raise SpotPartitionError(
            f"partition {partition!r} spans multiple configured subnets: "
            + ", ".join(sorted(subnet_ids))
        )

    return {instance_type: (instance_type, "regional") for instance_type in sorted(instance_types)}


def _instance_metadata(
    instance_ids: Sequence[str],
    *,
    region: str,
    profile: str | None,
    runner: CommandRunner,
) -> dict[str, tuple[str, str]]:
    args = _aws_base(region, profile)
    args.extend(["describe-instances", "--instance-ids", *instance_ids, "--output", "json"])
    payload = _json_from_command(args, runner=runner)
    metadata: dict[str, tuple[str, str]] = {}
    for reservation in payload.get("Reservations", []):
        if not isinstance(reservation, dict):
            continue
        for instance in reservation.get("Instances", []):
            if not isinstance(instance, dict):
                continue
            instance_type = str(instance.get("InstanceType") or "").strip()
            placement = instance.get("Placement") if isinstance(instance.get("Placement"), dict) else {}
            az = str(placement.get("AvailabilityZone") or "").strip()
            if instance_type and az:
                metadata[instance_type] = (instance_type, az)
    if not metadata:
        raise SpotPartitionError("AWS describe-instances returned no instance type/AZ metadata")
    return metadata


def _vcpu_counts(
    instance_types: Iterable[str],
    *,
    region: str,
    profile: str | None,
    runner: CommandRunner,
) -> dict[str, int]:
    unique = sorted(set(instance_types))
    args = _aws_base(region, profile)
    args.extend(["describe-instance-types", "--instance-types", *unique, "--output", "json"])
    payload = _json_from_command(args, runner=runner)
    counts: dict[str, int] = {}
    for item in payload.get("InstanceTypes", []):
        if not isinstance(item, dict):
            continue
        name = str(item.get("InstanceType") or "")
        info = item.get("VCpuInfo") if isinstance(item.get("VCpuInfo"), dict) else {}
        try:
            counts[name] = int(info["DefaultVCpus"])
        except (KeyError, TypeError, ValueError) as exc:
            raise SpotPartitionError(f"invalid vCPU metadata for {name}") from exc
    missing = sorted(set(unique).difference(counts))
    if missing:
        raise SpotPartitionError("missing vCPU metadata for instance types: " + ", ".join(missing))
    return counts


def _spot_price(
    instance_type: str,
    *,
    region: str,
    availability_zone: str,
    profile: str | None,
    runner: CommandRunner,
) -> float:
    args = _aws_base(region, profile)
    if availability_zone != "regional":
        args.extend(["describe-spot-price-history", "--availability-zone", availability_zone])
    else:
        args.append("describe-spot-price-history")
    args.extend(
        [
            "--instance-types",
            instance_type,
            "--product-descriptions",
            "Linux/UNIX",
            "--max-results",
            "20" if availability_zone == "regional" else "1",
            "--output",
            "json",
        ]
    )
    payload = _json_from_command(args, runner=runner)
    history = payload.get("SpotPriceHistory") or []
    if not history:
        raise SpotPartitionError(
            f"no current Spot price returned for {instance_type} in {availability_zone}"
        )
    prices: list[float] = []
    for item in history:
        if not isinstance(item, dict):
            continue
        try:
            prices.append(float(item["SpotPrice"]))
        except (KeyError, TypeError, ValueError) as exc:
            raise SpotPartitionError(
                f"invalid Spot price payload for {instance_type} in {availability_zone}"
            ) from exc
    if prices:
        return statistics.median(prices)
    try:
        return float(history[0]["SpotPrice"])
    except (KeyError, TypeError, ValueError) as exc:
        raise SpotPartitionError(
            f"invalid Spot price payload for {instance_type} in {availability_zone}"
        ) from exc


def _calculate_partition_costs(
    partitions: Sequence[str],
    *,
    region: str,
    profile: str | None,
    now: float,
    runner: CommandRunner,
) -> list[PartitionCost]:
    costs: list[PartitionCost] = []
    created_iso = datetime.fromtimestamp(now, timezone.utc).isoformat()
    for partition in partitions:
        nodes = _nodes_for_partition(partition, runner=runner)
        node_metadata = _node_metadata(nodes, runner=runner)
        instance_ids = _node_instance_ids(
            node_metadata,
            region=region,
            profile=profile,
            runner=runner,
        )
        if instance_ids:
            metadata = _instance_metadata(
                instance_ids,
                region=region,
                profile=profile,
                runner=runner,
            )
        else:
            metadata = _parallelcluster_instance_metadata(
                partition,
                node_metadata,
                region=region,
                profile=profile,
                runner=runner,
            )
        instance_types = sorted(metadata)
        azs = sorted({az for _, az in metadata.values()})
        if len(azs) != 1:
            raise SpotPartitionError(
                f"partition {partition!r} spans multiple AZs; observed {', '.join(azs)}"
            )
        az = azs[0]
        vcpus = _vcpu_counts(instance_types, region=region, profile=profile, runner=runner)
        samples = tuple(
            (
                instance_type,
                _spot_price(
                    instance_type,
                    region=region,
                    availability_zone=az,
                    profile=profile,
                    runner=runner,
                )
                / float(vcpus[instance_type]),
            )
            for instance_type in instance_types
        )
        costs.append(
            PartitionCost(
                partition=partition,
                median_usd_per_vcpu_hr=statistics.median(price for _, price in samples),
                instance_types=tuple(instance_types),
                price_samples=samples,
                created_at_epoch=now,
                created_at_iso=created_iso,
                region=region,
                availability_zone=az,
            )
        )
    return costs


def _parse_cache(path: Path) -> dict[str, PartitionCost]:
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            if tuple(reader.fieldnames or ()) != CACHE_HEADER:
                raise SpotPartitionError(f"partition cost cache has invalid header: {path}")
            costs: dict[str, PartitionCost] = {}
            for row in reader:
                try:
                    partition = str(row["partition"]).strip()
                    price_samples_payload = json.loads(row["price_samples_json"])
                    samples = tuple(
                        (str(item["instance_type"]), float(item["usd_per_vcpu_hr"]))
                        for item in price_samples_payload
                    )
                    if not partition or not samples:
                        raise ValueError("empty partition or price samples")
                    costs[partition] = PartitionCost(
                        partition=partition,
                        median_usd_per_vcpu_hr=float(row["median_usd_per_vcpu_hr"]),
                        instance_types=tuple(
                            item.strip()
                            for item in row["instance_types"].split(",")
                            if item.strip()
                        ),
                        price_samples=samples,
                        created_at_epoch=float(row["created_at_epoch"]),
                        created_at_iso=str(row["created_at_iso"]),
                        region=str(row["region"]),
                        availability_zone=str(row["availability_zone"]),
                    )
                except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
                    raise SpotPartitionError(f"malformed partition cost cache row in {path}") from exc
    except FileNotFoundError as exc:
        raise SpotPartitionError(f"partition cost cache not found: {path}") from exc
    if not costs:
        raise SpotPartitionError(f"partition cost cache is empty: {path}")
    return costs


def _cache_is_fresh(costs: Mapping[str, PartitionCost], *, now: float) -> bool:
    newest = max(cost.created_at_epoch for cost in costs.values())
    return 0 <= now - newest < CACHE_TTL_SECONDS


def _write_cache(path: Path, costs: Sequence[PartitionCost]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        newline="",
        dir=str(path.parent),
        prefix=path.name + ".",
        suffix=".tmp",
        delete=False,
    ) as handle:
        tmp_path = Path(handle.name)
        writer = csv.DictWriter(handle, fieldnames=CACHE_HEADER, delimiter="\t")
        writer.writeheader()
        for cost in costs:
            writer.writerow(
                {
                    "created_at_epoch": f"{cost.created_at_epoch:.6f}",
                    "created_at_iso": cost.created_at_iso,
                    "region": cost.region,
                    "availability_zone": cost.availability_zone,
                    "partition": cost.partition,
                    "median_usd_per_vcpu_hr": f"{cost.median_usd_per_vcpu_hr:.12f}",
                    "instance_types": ",".join(cost.instance_types),
                    "price_samples_json": json.dumps(
                        [
                            {
                                "instance_type": instance_type,
                                "usd_per_vcpu_hr": price,
                            }
                            for instance_type, price in cost.price_samples
                        ],
                        sort_keys=True,
                    ),
                }
            )
    os.replace(tmp_path, path)


def _refresh_cache(
    partitions: Sequence[str],
    *,
    cache_path: Path,
    env: Mapping[str, str],
    now: float,
    runner: CommandRunner,
) -> dict[str, PartitionCost]:
    region = _env_region(env)
    profile = str(env.get("AWS_PROFILE") or "").strip() or None
    lock_path = cache_path.with_name(cache_path.name + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        try:
            try:
                cached = _parse_cache(cache_path)
                if _cache_is_fresh(cached, now=now) and set(partitions).issubset(cached):
                    return cached
            except SpotPartitionError:
                pass
            costs = _calculate_partition_costs(
                partitions,
                region=region,
                profile=profile,
                now=now,
                runner=runner,
            )
            _write_cache(cache_path, costs)
            return {cost.partition: cost for cost in costs}
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


def _costs_for_partitions(
    partitions: Sequence[str],
    *,
    cache_path: Path,
    env: Mapping[str, str],
    now: float,
    runner: CommandRunner,
) -> dict[str, PartitionCost]:
    try:
        cached = _parse_cache(cache_path)
        if _cache_is_fresh(cached, now=now) and set(partitions).issubset(cached):
            return cached
    except SpotPartitionError:
        pass
    costs = _refresh_cache(
        partitions,
        cache_path=cache_path,
        env=env,
        now=now,
        runner=runner,
    )
    if not set(partitions).issubset(costs):
        missing = sorted(set(partitions).difference(costs))
        raise SpotPartitionError(
            "partition cost refresh did not produce requested partition(s): "
            + ", ".join(missing)
        )
    return costs


def derive_partition_order(
    partition_csv: str,
    *,
    env: Mapping[str, str] | None = None,
    now: float | None = None,
    cache_path: Path | None = None,
    runner: CommandRunner = _run_command,
) -> str:
    """Return requested partitions ordered by live median Spot cost per vCPU."""
    parts = _split_partition_csv(partition_csv)
    env_map = os.environ if env is None else env
    if (
        env_map.get("DAY_PROFILE") != "slurm"
        or env_map.get("PARTITION_MAGIC") == "0"
        or env_map.get("SLURM_JOB_ID")
    ):
        return ",".join(parts)
    effective_now = time.time() if now is None else now
    costs = _costs_for_partitions(
        parts,
        cache_path=PARTITION_COST_LOG if cache_path is None else cache_path,
        env=env_map,
        now=effective_now,
        runner=runner,
    )
    ordered = sorted(
        enumerate(parts),
        key=lambda item: (costs[item[1]].median_usd_per_vcpu_hr, item[0]),
    )
    return ",".join(part for _, part in ordered)


def _format_prices(costs: Iterable[PartitionCost]) -> str:
    lines = []
    for cost in costs:
        samples = ",".join(
            f"{instance_type}={price:.12f}" for instance_type, price in cost.price_samples
        )
        lines.append(
            f"{cost.partition}: median_usd_per_vcpu_hr={cost.median_usd_per_vcpu_hr:.12f} {samples}"
        )
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    partitions = _split_partition_csv(",".join(argv or sys.argv[1:]))
    try:
        costs = _refresh_cache(
            partitions,
            cache_path=PARTITION_COST_LOG,
            env=os.environ,
            now=time.time(),
            runner=_run_command,
        )
    except SpotPartitionError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(_format_prices(costs[partition] for partition in partitions), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
