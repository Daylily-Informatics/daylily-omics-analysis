#!/usr/bin/env python3
"""Generate GIAB HG001-HG007 Illumina 5x manifests."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


SAMPLE_IDS = ("HG001", "HG002", "HG003", "HG004", "HG005", "HG006", "HG007")
DEFAULT_SOURCE_SAMPLES = Path(".test_data/data/giab_30x_hg38_analysis_manifest.samples.tsv")
DEFAULT_FASTQ_ROOT = Path(
    "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/"
    "NovaSeqX_WHGS_TruSeqPF_HG002-007"
)
DEFAULT_OUTPUT_DIR = Path("config")

RUN_ID = "giab7-5x-20260425"
EXPERIMENT_ID = "ilmn5x"
SUBSAMPLE_PCT = "0.1666666667"

UNIT_FIELDS = [
    "RUNID",
    "SAMPLEID",
    "EXPERIMENTID",
    "LANEID",
    "BARCODEID",
    "LIBPREP",
    "SEQ_VENDOR",
    "SEQ_PLATFORM",
    "ILMN_R1_PATH",
    "ILMN_R2_PATH",
    "PACBIO_R1_PATH",
    "PACBIO_R2_PATH",
    "ONT_R1_PATH",
    "ONT_R2_PATH",
    "UG_R1_PATH",
    "UG_R2_PATH",
    "SUBSAMPLE_PCT",
    "ILMN_TRIM_READ_LENGTH",
    "SAMPLEUSE",
    "BWA_KMER",
    "DEEP_MODEL",
    "ULTIMA_CRAM",
    "ULTIMA_CRAM_ALIGNER",
    "ULTIMA_CRAM_SNV_CALLER",
    "ONT_CRAM",
    "ONT_CRAM_ALIGNER",
    "ONT_CRAM_SNV_CALLER",
    "PB_BAM",
    "PB_BAM_ALIGNER",
    "PB_BAM_SNV_CALLER",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--source-samples", type=Path, default=DEFAULT_SOURCE_SAMPLES)
    parser.add_argument("--fastq-root", type=Path, default=DEFAULT_FASTQ_ROOT)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--samples-out", type=Path)
    parser.add_argument("--units-out", type=Path)
    parser.add_argument(
        "--check-inputs",
        action="store_true",
        help="Require every expected FASTQ to exist as a non-empty regular file.",
    )
    return parser.parse_args()


def load_samples(path: Path) -> tuple[list[str], dict[str, dict[str, str]]]:
    if not path.is_file():
        raise SystemExit(f"ERROR: source samples file does not exist: {path}")

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"ERROR: source samples file has no header: {path}")
        if "SAMPLEID" not in reader.fieldnames:
            raise SystemExit(f"ERROR: source samples file is missing SAMPLEID: {path}")

        by_sample: dict[str, dict[str, str]] = {}
        for line_number, row in enumerate(reader, start=2):
            if not row or not any((value or "").strip() for value in row.values()):
                continue
            sample_id = (row.get("SAMPLEID") or "").strip()
            if not sample_id:
                raise SystemExit(f"ERROR: missing SAMPLEID at {path}:{line_number}")
            if sample_id in by_sample:
                raise SystemExit(f"ERROR: duplicate SAMPLEID {sample_id} in {path}")
            by_sample[sample_id] = {field: (row.get(field) or "") for field in reader.fieldnames}

    missing = [sample_id for sample_id in SAMPLE_IDS if sample_id not in by_sample]
    if missing:
        raise SystemExit(
            "ERROR: source samples file is missing required GIAB samples: "
            + ", ".join(missing)
        )

    return list(reader.fieldnames), by_sample


def fastq_paths(fastq_root: Path, sample_id: str) -> tuple[Path, Path]:
    return (
        fastq_root / f"{sample_id}_30x_R1.fastq.gz",
        fastq_root / f"{sample_id}_30x_R2.fastq.gz",
    )


def check_fastqs(fastq_root: Path) -> None:
    invalid: list[str] = []
    for sample_id in SAMPLE_IDS:
        for path in fastq_paths(fastq_root, sample_id):
            if not path.is_file():
                invalid.append(f"{path} (missing or not a regular file)")
            elif path.stat().st_size <= 0:
                invalid.append(f"{path} (empty file)")

    if invalid:
        raise SystemExit(
            "ERROR: expected GIAB Illumina FASTQs failed validation:\n"
            + "\n".join(f"  - {item}" for item in invalid)
        )


def build_unit_row(sample_id: str, fastq_root: Path) -> dict[str, str]:
    r1_path, r2_path = fastq_paths(fastq_root, sample_id)
    row = {field: "" for field in UNIT_FIELDS}
    row.update(
        {
            "RUNID": RUN_ID,
            "SAMPLEID": sample_id,
            "EXPERIMENTID": EXPERIMENT_ID,
            "LANEID": "0",
            "BARCODEID": "D0",
            "LIBPREP": "PCR-FREE",
            "SEQ_VENDOR": "ILMN",
            "SEQ_PLATFORM": "NOVASEQ",
            "ILMN_R1_PATH": str(r1_path),
            "ILMN_R2_PATH": str(r2_path),
            "SUBSAMPLE_PCT": SUBSAMPLE_PCT,
            "SAMPLEUSE": "posControl",
            "BWA_KMER": "19",
        }
    )
    return row


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            delimiter="\t",
            lineterminator="\n",
            extrasaction="raise",
        )
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    args = parse_args()
    samples_out = args.samples_out or args.output_dir / "samples.tsv"
    units_out = args.units_out or args.output_dir / "units.tsv"

    sample_fields, source_samples = load_samples(args.source_samples)
    if args.check_inputs:
        check_fastqs(args.fastq_root)

    sample_rows = [source_samples[sample_id] for sample_id in SAMPLE_IDS]
    unit_rows = [build_unit_row(sample_id, args.fastq_root) for sample_id in SAMPLE_IDS]

    write_tsv(samples_out, sample_fields, sample_rows)
    write_tsv(units_out, UNIT_FIELDS, unit_rows)

    print(f"Wrote {len(sample_rows)} sample rows to {samples_out}")
    print(f"Wrote {len(unit_rows)} unit rows to {units_out}")
    if args.check_inputs:
        print(f"Validated expected FASTQs under {args.fastq_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
