from __future__ import annotations

import json
from pathlib import Path

import yaml

from daylily_omics_analysis.slurm.spot_partition_order import update_rule_config


def _fake_runner(args):
    if "describe-instance-types" in args:
        start = args.index("--instance-types") + 1
        end = args.index("--output")
        return json.dumps(
            {
                "InstanceTypes": [
                    {"InstanceType": instance_type}
                    for instance_type in args[start:end]
                ]
            }
        )
    if "describe-spot-price-history" in args:
        instance_type = args[args.index("--instance-types") + 1]
        price = "2.0" if instance_type.startswith("c8id.48") else "8.0"
        if instance_type.startswith("m8id.48"):
            price = "3.0"
        if instance_type.startswith("r8id.48"):
            price = "4.0"
        return json.dumps({"SpotPriceHistory": [{"SpotPrice": price}]})
    raise AssertionError(args)


def test_update_rule_config_orders_bwa_partitions_by_average_spot_price(tmp_path: Path) -> None:
    path = tmp_path / "rule_config.yaml"
    path.write_text(
        """# keep this comment
bwa_mem2a_aln_sort:
  partition: i384nvme,i192nvme
  partition_strategy: spot_price_runtime
  spot_price_region: us-west-2
  spot_price_availability_zone: us-west-2d
  allowed_partitions:
  - i384nvme
  - i192nvme
  partition_instance_catalog:
    i384nvme:
    - c8id.96xlarge
    - m8id.96xlarge
    i192nvme:
    - c8id.48xlarge
    - m8id.48xlarge
""",
        encoding="utf-8",
    )

    ordered, prices = update_rule_config(path, runner=_fake_runner)

    assert ordered == "i192nvme,i384nvme"
    assert [price.partition for price in prices] == ["i192nvme", "i384nvme"]
    assert path.read_text(encoding="utf-8").startswith("# keep this comment\n")
    updated = yaml.safe_load(path.read_text(encoding="utf-8"))
    assert updated["bwa_mem2a_aln_sort"]["partition"] == "i192nvme,i384nvme"
