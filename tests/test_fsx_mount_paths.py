from __future__ import annotations

import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

HISTORICAL_PREFIXES = ("docs/plans/", "docs/jem_working_docs/plans/", "quarantine/")
RETIRED_PATHS = (
    "/fsx/" + "data",
    "/fsx/" + "runtime_assets",
    "/fsx/" + "staged_sample_data",
)
GIAB_HG38_TRUTH_ROOT = (
    "/fsx/references/genomic_data/organism_annotations/"
    "H_sapiens/hg38/controls/giab/snv/v4.2.1"
)


def _tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def test_active_tracked_files_use_current_dyec_mount_contract() -> None:
    offenders: list[str] = []

    for relpath in _tracked_files():
        if relpath.startswith(HISTORICAL_PREFIXES):
            continue

        path = REPO_ROOT / relpath
        text = path.read_text(encoding="utf-8", errors="ignore")
        for retired_path in RETIRED_PATHS:
            if retired_path in text:
                offenders.append(f"{relpath}: contains {retired_path}")

    assert offenders == []


def test_giab_hg38_concordance_data_stays_on_reference_annotations_mount() -> None:
    manifest = _read_text("giab_30x_hg38_analysis_manifest.csv")
    template = _read_text("etc/analysis_samples_template.tsv")

    for sample_id in ("HG001", "HG002", "HG003", "HG004", "HG005", "HG006", "HG007"):
        assert f"{GIAB_HG38_TRUTH_ROOT}/{sample_id}/" in manifest

    assert f"{GIAB_HG38_TRUTH_ROOT}/HG002/" in template
    assert "/fsx/control_data/genomic_data/organism_annotations/" not in manifest
    assert "/fsx/control_data/genomic_data/organism_annotations/" not in template


def _read_text(relpath: str) -> str:
    return (REPO_ROOT / relpath).read_text(encoding="utf-8")
