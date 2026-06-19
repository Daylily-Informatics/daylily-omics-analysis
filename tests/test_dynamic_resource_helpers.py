from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest

from daylily_omics_analysis.slurm import spot_partition_order as spo
from daylily_omics_analysis.slurm.spot_partition_order import (
    CACHE_HEADER,
    SpotPartitionError,
    derive_partition_order,
)
from daylily_omics_analysis.workflow_resources import (
    ResourceConfigError,
    derive_doppelmark_mem_mb,
)


REPO_ROOT = Path(__file__).resolve().parents[1]


def _doppelmark_section(**overrides):
    section = {
        "mem_mb": 800000,
        "dynamic_mem_mb": True,
        "dynamic_mem_floor_mb": 512000,
        "dynamic_mem_per_gib_mb": 6144,
        "dynamic_mem_cap_mb": 800000,
        "dynamic_mem_round_mb": 1000,
    }
    section.update(overrides)
    return section


def _runner(args):
    if args[:5] == ["sinfo", "-h", "-p", "cheap", "-N"]:
        return "cheap-node\n"
    if args[:5] == ["sinfo", "-h", "-p", "costly", "-N"]:
        return "costly-node\n"
    if args[:5] == ["sinfo", "-h", "-p", "missing", "-N"]:
        return ""
    if args[:4] == ["scontrol", "show", "node", "-o"]:
        node = args[4]
        return {
            "cheap-node": "NodeName=cheap-node InstanceId=i-cheap",
            "costly-node": "NodeName=costly-node InstanceId=i-costly",
        }[node]
    if "describe-instances" in args and "--instance-ids" in args:
        ids = args[args.index("--instance-ids") + 1 : args.index("--output")]
        mapping = {
            "i-cheap": ("c8id.large", "us-west-2a"),
            "i-costly": ("r8id.large", "us-west-2a"),
        }
        return json.dumps(
            {
                "Reservations": [
                    {
                        "Instances": [
                            {
                                "InstanceId": instance_id,
                                "InstanceType": mapping[instance_id][0],
                                "Placement": {"AvailabilityZone": mapping[instance_id][1]},
                            }
                            for instance_id in ids
                        ]
                    }
                ]
            }
        )
    if "describe-instance-types" in args:
        start = args.index("--instance-types") + 1
        end = args.index("--output")
        return json.dumps(
            {
                "InstanceTypes": [
                    {
                        "InstanceType": instance_type,
                        "VCpuInfo": {"DefaultVCpus": 2},
                    }
                    for instance_type in args[start:end]
                ]
            }
        )
    if "describe-spot-price-history" in args:
        instance_type = args[args.index("--instance-types") + 1]
        price = {"c8id.large": "0.10", "r8id.large": "0.50"}[instance_type]
        return json.dumps({"SpotPriceHistory": [{"SpotPrice": price}]})
    raise AssertionError(args)


def _fresh_cache(path: Path, now: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\t".join(CACHE_HEADER)
        + "\n"
        + "\t".join(
            [
                f"{now:.6f}",
                "2026-06-19T00:00:00+00:00",
                "us-west-2",
                "us-west-2a",
                "cached",
                "0.010000000000",
                "c8id.large",
                '[{"instance_type": "c8id.large", "usd_per_vcpu_hr": 0.01}]',
            ]
        )
        + "\n",
        encoding="utf-8",
    )


def _rule_block(text: str, rule_name: str) -> str:
    start = text.index(f"rule {rule_name}:")
    next_rule = text.find("\nrule ", start + 1)
    return text[start:] if next_rule == -1 else text[start:next_rule]


def test_doppelmark_memory_passes_through_outside_slurm(tmp_path: Path) -> None:
    missing = tmp_path / "missing.bam"
    assert (
        derive_doppelmark_mem_mb(missing, _doppelmark_section(mem_mb=50000), day_profile="local")
        == 50000
    )


def test_doppelmark_memory_uses_floor_rounding_and_cap(tmp_path: Path) -> None:
    small = tmp_path / "small.bam"
    small.write_bytes(b"x")
    assert derive_doppelmark_mem_mb(small, _doppelmark_section(), day_profile="slurm") == 512000

    hundred_gib = tmp_path / "hundred-gib.bam"
    hundred_gib.touch()
    os.truncate(hundred_gib, 100 * 1024**3)
    assert (
        derive_doppelmark_mem_mb(hundred_gib, _doppelmark_section(), day_profile="slurm")
        == 615000
    )

    huge = tmp_path / "huge.bam"
    huge.touch()
    os.truncate(huge, 200 * 1024**3)
    assert derive_doppelmark_mem_mb(huge, _doppelmark_section(), day_profile="slurm") == 800000


def test_doppelmark_memory_fails_hard_for_missing_input_or_bad_config(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError, match="not readable"):
        derive_doppelmark_mem_mb(tmp_path / "missing.bam", _doppelmark_section(), day_profile="slurm")

    bam = tmp_path / "input.bam"
    bam.write_bytes(b"x")
    with pytest.raises(ResourceConfigError, match="positive integer"):
        derive_doppelmark_mem_mb(
            bam,
            _doppelmark_section(dynamic_mem_round_mb=0),
            day_profile="slurm",
        )


def test_partition_order_passes_through_for_local_or_partition_magic(tmp_path: Path) -> None:
    cache = tmp_path / "partition_costs.log"
    assert derive_partition_order("costly,cheap", env={"DAY_PROFILE": "local"}, cache_path=cache) == "costly,cheap"
    assert (
        derive_partition_order(
            "costly,cheap",
            env={"DAY_PROFILE": "slurm", "PARTITION_MAGIC": "0"},
            cache_path=cache,
        )
        == "costly,cheap"
    )


def test_partition_order_refreshes_stale_cache_and_sorts_by_vcpu_cost(tmp_path: Path) -> None:
    cache = tmp_path / "partition_costs.log"
    _fresh_cache(cache, now=time.time() - 3600)
    ordered = derive_partition_order(
        "costly,cheap",
        env={"DAY_PROFILE": "slurm", "AWS_REGION": "us-west-2"},
        now=time.time(),
        cache_path=cache,
        runner=_runner,
    )

    assert ordered == "cheap,costly"
    assert "cheap" in cache.read_text(encoding="utf-8")
    assert (tmp_path / "partition_costs.log.lock").exists()


def test_partition_order_uses_fresh_cache_without_live_commands(tmp_path: Path) -> None:
    cache = tmp_path / "partition_costs.log"
    _fresh_cache(cache, now=1000.0)

    def fail_runner(args):
        raise AssertionError(args)

    assert (
        derive_partition_order(
            "cached",
            env={"DAY_PROFILE": "slurm"},
            now=1100.0,
            cache_path=cache,
            runner=fail_runner,
        )
        == "cached"
    )


def test_partition_order_lock_is_taken_during_refresh(tmp_path: Path, monkeypatch) -> None:
    cache = tmp_path / "partition_costs.log"
    calls = []

    def record_flock(fd, operation):
        calls.append(operation)

    monkeypatch.setattr(spo.fcntl, "flock", record_flock)

    assert (
        derive_partition_order(
            "cheap,costly",
            env={"DAY_PROFILE": "slurm", "AWS_REGION": "us-west-2"},
            now=1000.0,
            cache_path=cache,
            runner=_runner,
        )
        == "cheap,costly"
    )
    assert calls == [spo.fcntl.LOCK_EX, spo.fcntl.LOCK_UN]


def test_partition_order_resolves_slurm_node_addresses_via_ec2_filters(tmp_path: Path) -> None:
    cache = tmp_path / "partition_costs.log"
    calls = []

    def address_runner(args):
        calls.append(args)
        if args[:5] == ["sinfo", "-h", "-p", "dns", "-N"]:
            return "dns-node\n"
        if args[:5] == ["sinfo", "-h", "-p", "ip", "-N"]:
            return "ip-node\n"
        if args[:4] == ["scontrol", "show", "node", "-o"]:
            return {
                "dns-node": "NodeName=dns-node NodeAddr=ip-10-0-0-10.us-west-2.compute.internal",
                "ip-node": "NodeName=ip-node NodeAddr=10.0.0.11",
            }[args[4]]
        if "describe-instances" in args and "--filters" in args:
            filter_value = args[args.index("--filters") + 1]
            instance_id = "i-dns" if "private-dns-name" in filter_value else "i-ip"
            return json.dumps({"Reservations": [{"Instances": [{"InstanceId": instance_id}]}]})
        if "describe-instances" in args and "--instance-ids" in args:
            ids = args[args.index("--instance-ids") + 1 : args.index("--output")]
            instance_type = "c8id.large" if ids == ["i-dns"] else "r8id.large"
            return json.dumps(
                {
                    "Reservations": [
                        {
                            "Instances": [
                                {
                                    "InstanceId": ids[0],
                                    "InstanceType": instance_type,
                                    "Placement": {"AvailabilityZone": "us-west-2a"},
                                }
                            ]
                        }
                    ]
                }
            )
        if "describe-instance-types" in args:
            start = args.index("--instance-types") + 1
            end = args.index("--output")
            return json.dumps(
                {
                    "InstanceTypes": [
                        {"InstanceType": instance_type, "VCpuInfo": {"DefaultVCpus": 2}}
                        for instance_type in args[start:end]
                    ]
                }
            )
        if "describe-spot-price-history" in args:
            instance_type = args[args.index("--instance-types") + 1]
            price = "0.10" if instance_type == "c8id.large" else "0.20"
            return json.dumps({"SpotPriceHistory": [{"SpotPrice": price}]})
        raise AssertionError(args)

    assert (
        derive_partition_order(
            "ip,dns",
            env={"DAY_PROFILE": "slurm", "AWS_REGION": "us-west-2"},
            now=1000.0,
            cache_path=cache,
            runner=address_runner,
        )
        == "dns,ip"
    )
    assert any("private-dns-name" in " ".join(call) for call in calls)
    assert any("private-ip-address" in " ".join(call) for call in calls)


def test_partition_order_uses_parallelcluster_fleet_config_for_powered_down_nodes(
    tmp_path: Path,
    monkeypatch,
) -> None:
    cache = tmp_path / "partition_costs.log"
    fleet_config = tmp_path / "fleet-config.json"
    fleet_config.write_text(
        json.dumps(
            {
                "cheap": {
                    "cheapres": {
                        "Networking": {"SubnetIds": ["subnet-a"]},
                        "Instances": [{"InstanceType": "c8id.large"}],
                    }
                },
                "costly": {
                    "costlyres": {
                        "Networking": {"SubnetIds": ["subnet-a"]},
                        "Instances": [{"InstanceType": "r8id.large"}],
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(spo, "PARALLELCLUSTER_FLEET_CONFIG", fleet_config)
    calls = []

    def powered_down_runner(args):
        calls.append(args)
        if args[:5] == ["sinfo", "-h", "-p", "cheap", "-N"]:
            return "cheap-dy-cheapres-1\n"
        if args[:5] == ["sinfo", "-h", "-p", "costly", "-N"]:
            return "costly-dy-costlyres-1\n"
        if args[:4] == ["scontrol", "show", "node", "-o"]:
            node = args[4]
            partition, resource = node.split("-dy-", 1)
            resource = resource.rsplit("-", 1)[0]
            return (
                f"NodeName={node} AvailableFeatures=dynamic,{resource} "
                f"NodeAddr={node} NodeHostName={node} "
                f"State=IDLE+CLOUD+POWERED_DOWN Partitions={partition}"
            )
        if "describe-instances" in args and "--filters" in args:
            return json.dumps({"Reservations": []})
        if "describe-instance-types" in args:
            start = args.index("--instance-types") + 1
            end = args.index("--output")
            return json.dumps(
                {
                    "InstanceTypes": [
                        {"InstanceType": instance_type, "VCpuInfo": {"DefaultVCpus": 2}}
                        for instance_type in args[start:end]
                    ]
                }
            )
        if "describe-spot-price-history" in args:
            instance_type = args[args.index("--instance-types") + 1]
            price = "0.10" if instance_type == "c8id.large" else "0.50"
            return json.dumps({"SpotPriceHistory": [{"SpotPrice": price}]})
        raise AssertionError(args)

    assert (
        derive_partition_order(
            "costly,cheap",
            env={"DAY_PROFILE": "slurm", "AWS_REGION": "us-west-2"},
            now=1000.0,
            cache_path=cache,
            runner=powered_down_runner,
        )
        == "cheap,costly"
    )
    assert not any("describe-subnets" in call for call in calls)
    assert any("describe-instances" in call and "--filters" in call for call in calls)


def test_partition_order_fails_hard_on_malformed_cache_and_missing_live_metadata(tmp_path: Path) -> None:
    cache = tmp_path / "partition_costs.log"
    cache.write_text("bad\theader\n", encoding="utf-8")

    with pytest.raises(SpotPartitionError, match="sinfo returned no nodes"):
        derive_partition_order(
            "missing",
            env={"DAY_PROFILE": "slurm", "AWS_REGION": "us-west-2"},
            now=1000.0,
            cache_path=cache,
            runner=_runner,
        )


def test_primary_compute_rules_use_dynamic_partition_ordering() -> None:
    expected = {
        "workflow/rules/bwa_mem2a_align_sort.smk": ("bwa_mem2_sort",),
        "workflow/rules/doppel_mrkdups.smk": ("doppelmark_dups",),
        "workflow/rules/sent_DNAscope.smk": ("sent_DNAscope",),
        "workflow/rules/deepvariant_1_9.smk": ("deepvariant_19",),
        "workflow/rules/lofreq2.smk": ("lfq2_indelqual", "lofreq2"),
        "workflow/rules/aivariant.smk": ("aiv_bams", "aiv"),
        "workflow/rules/varnet.smk": ("varn",),
        "workflow/rules/strelka2.smk": ("strelka2_germline", "strelka2_somatic"),
        "workflow/rules/roche_sbxd.smk": ("roche_gatk_haplotypecaller", "roche_filter_variants"),
    }

    for relpath, rule_names in expected.items():
        text = (REPO_ROOT / relpath).read_text(encoding="utf-8")
        for rule_name in rule_names:
            assert "partition=derive_partition_order(" in _rule_block(text, rule_name)


def test_helper_rules_do_not_use_dynamic_partition_ordering() -> None:
    helpers = {
        "workflow/rules/sent_DNAscope.smk": ("sentD_sort_index_chunk_vcf",),
        "workflow/rules/deepvariant_1_9.smk": ("deep19_sort_index_chunk_vcf", "deep19_concat_index_chunks"),
        "workflow/rules/aivariant.smk": ("aiv_sort_index_chunk_vcf", "aiv_concat_index_chunks"),
        "workflow/rules/varnet.smk": ("varn_sort_index_chunk_vcf", "varn_concat_index_chunks"),
        "workflow/rules/strelka2.smk": ("strelka2_germline_concat", "strelka2_somatic_concat"),
    }

    for relpath, rule_names in helpers.items():
        text = (REPO_ROOT / relpath).read_text(encoding="utf-8")
        for rule_name in rule_names:
            assert "derive_partition_order(" not in _rule_block(text, rule_name)


def test_snakefile_adds_repo_root_to_import_path_before_rule_includes() -> None:
    text = (REPO_ROOT / "workflow/Snakefile").read_text(encoding="utf-8")
    path_insert = "sys.path.insert(0, wd)"
    include_common = 'include: "rules/global_common.smk"'

    assert path_insert in text
    assert text.index(path_insert) < text.index(include_common)
