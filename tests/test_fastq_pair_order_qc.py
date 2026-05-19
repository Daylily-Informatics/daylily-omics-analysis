from __future__ import annotations

import gzip
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
QC_SCRIPT = REPO_ROOT / "bin" / "qc_fastq_files_for_read_order_matching.sh"


def _write_fastq(path: Path, names: list[str], *, mate: str) -> None:
    suffix = "/1" if mate == "R1" else "/2"
    with gzip.open(path, "wt", encoding="utf-8") as handle:
        for name in names:
            handle.write(f"@{name}{suffix}\n")
            handle.write("ACGT\n")
            handle.write("+\n")
            handle.write("IIII\n")


def test_qc_fastq_pair_order_accepts_matching_first_last_and_sampled_reads(
    tmp_path: Path,
) -> None:
    r1 = tmp_path / "lane001.R1.fastq.gz"
    r2 = tmp_path / "lane001.R2.fastq.gz"
    _write_fastq(r1, ["read001", "read002", "read003", "read004"], mate="R1")
    _write_fastq(r2, ["read001", "read002", "read003", "read004"], mate="R2")

    result = subprocess.run(
        ["bash", str(QC_SCRIPT), "2", str(r1), str(r2)],
        check=False,
        text=True,
        capture_output=True,
    )

    assert result.returncode == 0
    assert "Paired correctly" in result.stdout
    assert "first=read001 last=read004" in result.stdout


def test_qc_fastq_pair_order_rejects_last_read_mismatch(tmp_path: Path) -> None:
    r1 = tmp_path / "lane001.R1.fastq.gz"
    r2 = tmp_path / "lane001.R2.fastq.gz"
    _write_fastq(r1, ["read001", "read002", "read003", "read004"], mate="R1")
    _write_fastq(r2, ["read001", "read002", "read003", "read999"], mate="R2")

    result = subprocess.run(
        ["bash", str(QC_SCRIPT), "2", str(r1), str(r2)],
        check=False,
        text=True,
        capture_output=True,
    )

    assert result.returncode == 1
    assert "Last read mismatch" in result.stdout
    assert "read004" in result.stdout
    assert "read999" in result.stdout

