from __future__ import annotations

import csv
import importlib.util
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_module():
    path = REPO_ROOT / "bin" / "util" / "write_peddy_low_data_outputs.py"
    spec = importlib.util.spec_from_file_location("write_peddy_low_data_outputs", path)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_write_peddy_low_data_outputs_has_required_files(tmp_path: Path) -> None:
    module = _load_module()
    ped = tmp_path / "sample.ped"
    ped.write_text("HG002\tHG002\t0\t0\t1\t0\n", encoding="utf-8")
    prefix = tmp_path / "HG002.sent.dmd.sentd.peddy."

    module.write_outputs(
        str(prefix),
        ped,
        "HG002",
        "peddy_no_usable_heterozygous_variants",
    )

    required = [
        "ped",
        "ped_check.csv",
        "sex_check.csv",
        "het_check.csv",
        "background_pca.json",
        "html",
        "vs.html",
        "ped_check.png",
        "het_check.png",
        "sex_check.png",
    ]
    for suffix in required:
        path = tmp_path / f"HG002.sent.dmd.sentd.peddy.{suffix}"
        assert path.is_file(), suffix
        assert path.stat().st_size > 0, suffix

    with (tmp_path / "HG002.sent.dmd.sentd.peddy.sex_check.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        sex_rows = list(csv.DictReader(handle))
    assert sex_rows == [
        {
            "sample_id": "HG002",
            "ped_sex": "male",
            "hom_ref_count": "0",
            "het_count": "0",
            "hom_alt_count": "0",
            "het_ratio": "",
            "predicted_sex": "UNKNOWN",
            "error": "true",
            "dayoa_status": "insufficient_variant_data",
            "dayoa_status_detail": "peddy_no_usable_heterozygous_variants",
        }
    ]

    with (tmp_path / "HG002.sent.dmd.sentd.peddy.het_check.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        het_rows = list(csv.DictReader(handle))
    assert het_rows[0]["dayoa_status"] == "insufficient_variant_data"
