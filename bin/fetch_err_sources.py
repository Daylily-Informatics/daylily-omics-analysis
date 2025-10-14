#!/usr/bin/env python3
"""Fetch ENA run data and build Daylily sample/unit tables.

This helper accepts one or more ENA run accessions (ERR_* identifiers).  It
looks up the associated experiment and sample metadata, downloads the
available read data (paired FASTQ, CRAM, or BAM), and writes ready-to-use
``samples.tsv`` and ``units.tsv`` files in ``./conf``.

The generated tables follow the Daylily schemas and include the optional
``AMPLIFICATION_TYPE`` and ``ALIGNED_REF_UID`` columns requested for the units
file.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import hashlib
import io
from pathlib import Path
import sys
import textwrap
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, Iterable, List, Sequence, Tuple

ENA_FILEREPORT_URL = "https://www.ebi.ac.uk/ena/portal/api/filereport"

RUN_FIELDS = [
    "run_accession",
    "experiment_accession",
    "sample_accession",
    "study_accession",
    "fastq_ftp",
    "fastq_md5",
    "fastq_bytes",
    "submitted_ftp",
    "submitted_md5",
    "submitted_bytes",
    "submitted_format",
    "submitted_cram_ftp",
    "submitted_cram_md5",
    "submitted_cram_bytes",
    "submitted_bam_ftp",
    "submitted_bam_md5",
    "submitted_bam_bytes",
    "library_layout",
    "library_selection",
    "library_source",
    "library_strategy",
    "library_name",
    "center_name",
    "instrument_model",
    "instrument_platform",
    "read_count",
]

EXPERIMENT_FIELDS = [
    "experiment_accession",
    "study_accession",
    "design_description",
    "library_layout",
    "library_selection",
    "library_source",
    "library_strategy",
    "instrument_model",
    "instrument_platform",
    "analysis_accession",
    "study_title",
]

SAMPLE_FIELDS = [
    "sample_accession",
    "sample_alias",
    "sample_title",
    "scientific_name",
    "sex",
    "collection_date",
    "description",
]

UNIT_COLUMNS = [
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
    "AMPLIFICATION_TYPE",
    "ALIGNED_REF_UID",
]

SAMPLE_COLUMNS = [
    "SAMPLEID",
    "SAMPLESOURCE",
    "SAMPLECLASS",
    "BIOLOGICAL_SEX",
    "CONCORDANCE_CONTROL_PATH",
    "IS_POSITIVE_CONTROL",
    "IS_NEGATIVE_CONTROL",
    "SAMPLE_TYPE",
    "TUM_NRM_SAMPLEID_MATCH",
    "EXTERNAL_SAMPLE_ID",
    "N_X",
    "N_Y",
    "TRUTH_DATA_DIR",
]


class EnaError(RuntimeError):
    """Raised when the ENA API cannot satisfy a request."""


def _http_get(url: str) -> str:
    try:
        with urllib.request.urlopen(url) as response:
            data = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:  # pragma: no cover - network failure handling
        raise EnaError(f"ENA request failed ({exc.code}): {exc.reason}") from exc
    except urllib.error.URLError as exc:  # pragma: no cover - network failure handling
        raise EnaError(f"Unable to contact ENA: {exc.reason}") from exc
    return data


def _fetch_ena_records(
    result: str,
    accessions: Sequence[str],
    fields: Sequence[str],
    key_field: str,
) -> Dict[str, Dict[str, str]]:
    unique = sorted(set(a for a in accessions if a))
    if not unique:
        return {}
    params = {
        "result": result,
        "accession": ",".join(unique),
        "fields": ",".join(fields),
        "format": "tsv",
    }
    url = f"{ENA_FILEREPORT_URL}?{urllib.parse.urlencode(params)}"
    text = _http_get(url)
    if not text.strip():
        return {}
    reader = csv.DictReader(io.StringIO(text), delimiter="\t")
    records: Dict[str, Dict[str, str]] = {}
    for row in reader:
        key = (row.get(key_field) or "").strip()
        if key:
            records[key] = {k: (v or "").strip() for k, v in row.items()}
    return records


def _split_values(raw: str) -> List[str]:
    if not raw:
        return []
    values = []
    for part in raw.split(";"):
        part = part.strip()
        if part:
            values.append(part)
    return values


def _normalise_remote(remote: str) -> str:
    remote = remote.strip()
    if not remote:
        return remote
    if remote.startswith("http://") or remote.startswith("https://"):
        return remote
    if remote.startswith("ftp://"):
        remote = remote[len("ftp://") :]
    if remote.startswith("ftp.sra.ebi.ac.uk"):
        return f"https://{remote}"
    if remote.startswith("era-fasp@"):
        raise EnaError(
            "Aspera-only paths were returned. Please configure Aspera manually for: "
            f"{remote}"
        )
    if remote.startswith("//"):
        return f"https:{remote}"
    # Fallback: assume bare host/path
    return f"https://{remote}"


def _ensure_even_fastq(run_id: str, run_meta: Dict[str, str]) -> None:
    layout = (run_meta.get("library_layout") or "").strip().upper()
    fastq_files = _split_values(run_meta.get("fastq_ftp", ""))
    if layout == "SINGLE":
        raise EnaError(
            f"Run {run_id} is single-end; paired FASTQ data is required."
        )
    if fastq_files and len(fastq_files) % 2 != 0:
        raise EnaError(
            f"Run {run_id} reports an odd number of FASTQ files: {fastq_files}"
        )


def _md5(path: Path) -> str:
    hash_md5 = hashlib.md5()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8192), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def _download(url: str, destination: Path, expected_md5: str | None = None) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, destination.open("wb") as handle:  # pragma: no cover - network
        while True:
            chunk = response.read(8192)
            if not chunk:
                break
            handle.write(chunk)
    if expected_md5:
        checksum = _md5(destination)
        if checksum.lower() != expected_md5.lower():
            destination.unlink(missing_ok=True)
            raise EnaError(
                f"Checksum mismatch for {destination} (expected {expected_md5}, got {checksum})."
            )


def _plan_run_download(
    run_id: str,
    run_meta: Dict[str, str],
    download_dir: Path,
) -> Tuple[str, List[Tuple[str, Path, str]]]:
    fastq_files = _split_values(run_meta.get("fastq_ftp", ""))
    fastq_md5 = _split_values(run_meta.get("fastq_md5", ""))
    cram_files = _split_values(run_meta.get("submitted_cram_ftp", ""))
    cram_md5 = _split_values(run_meta.get("submitted_cram_md5", ""))
    bam_files = _split_values(run_meta.get("submitted_bam_ftp", ""))
    bam_md5 = _split_values(run_meta.get("submitted_bam_md5", ""))

    target_dir = download_dir / run_id

    if fastq_files:
        if len(fastq_files) < 2:
            raise EnaError(
                f"Run {run_id} does not provide a complete paired FASTQ set."
            )
        r1 = _normalise_remote(fastq_files[0])
        r2 = _normalise_remote(fastq_files[1])
        dl = [
            (r1, target_dir / Path(fastq_files[0]).name, fastq_md5[0] if fastq_md5 else None),
            (r2, target_dir / Path(fastq_files[1]).name, fastq_md5[1] if len(fastq_md5) > 1 else None),
        ]
        return "fastq", dl

    if cram_files:
        cram_url = _normalise_remote(cram_files[0])
        md5 = cram_md5[0] if cram_md5 else None
        return "cram", [(cram_url, target_dir / Path(cram_files[0]).name, md5)]

    if bam_files:
        bam_url = _normalise_remote(bam_files[0])
        md5 = bam_md5[0] if bam_md5 else None
        return "bam", [(bam_url, target_dir / Path(bam_files[0]).name, md5)]

    raise EnaError(
        f"Run {run_id} does not expose FASTQ, CRAM, or BAM data for download."
    )


def _normalise_sex(raw: str) -> str:
    value = (raw or "").strip().lower()
    if value.startswith("m"):
        return "male"
    if value.startswith("f"):
        return "female"
    return "na"


def build_units_row(
    run_meta: Dict[str, str],
    experiment_meta: Dict[str, str],
    download_type: str,
    downloads: List[Tuple[str, Path, str]],
) -> Dict[str, str]:
    row = {column: "" for column in UNIT_COLUMNS}

    run_id = run_meta.get("run_accession", "")
    sample_id = run_meta.get("sample_accession", "")
    experiment_id = run_meta.get("experiment_accession", "")
    instrument = run_meta.get("instrument_platform") or run_meta.get("instrument_model") or "UNKNOWN"
    libprep = run_meta.get("library_selection") or run_meta.get("library_strategy") or "UNKNOWN"
    vendor = run_meta.get("center_name") or "UNKNOWN"

    row.update(
        {
            "RUNID": run_id,
            "SAMPLEID": sample_id,
            "EXPERIMENTID": experiment_id,
            "LANEID": run_meta.get("lane_id", "1"),
            "BARCODEID": run_meta.get("barcode", "na"),
            "LIBPREP": libprep,
            "SEQ_VENDOR": vendor,
            "SEQ_PLATFORM": instrument,
            "SUBSAMPLE_PCT": "na",
            "SAMPLEUSE": "research",
            "BWA_KMER": "19",
            "DEEP_MODEL": "WGS",
            "ULTIMA_CRAM_ALIGNER": "na",
            "ULTIMA_CRAM_SNV_CALLER": "na",
            "ONT_CRAM_ALIGNER": "na",
            "ONT_CRAM_SNV_CALLER": "na",
            "PB_BAM_ALIGNER": "na",
            "PB_BAM_SNV_CALLER": "na",
            "AMPLIFICATION_TYPE": experiment_meta.get("library_selection")
            or run_meta.get("library_selection", ""),
            "ALIGNED_REF_UID": experiment_meta.get("analysis_accession")
            or experiment_meta.get("study_accession", ""),
        }
    )

    if download_type == "fastq":
        if len(downloads) >= 2:
            row["ILMN_R1_PATH"] = str(downloads[0][1])
            row["ILMN_R2_PATH"] = str(downloads[1][1])
        # Clear cram/bam columns
        row["ULTIMA_CRAM"] = ""
        row["ONT_CRAM"] = ""
        row["PB_BAM"] = ""
    elif download_type == "cram":
        cram_path = str(downloads[0][1])
        row["ULTIMA_CRAM"] = cram_path
        row["ONT_CRAM"] = cram_path if "ONT" in instrument.upper() else ""
        row["PB_BAM"] = ""
    elif download_type == "bam":
        bam_path = str(downloads[0][1])
        row["PB_BAM"] = bam_path
        row["ULTIMA_CRAM"] = ""
        row["ONT_CRAM"] = ""
    else:
        raise ValueError(f"Unsupported download type: {download_type}")

    return row


def build_sample_row(
    sample_id: str,
    run_meta: Dict[str, str],
    sample_meta: Dict[str, str],
) -> Dict[str, str]:
    scientific_name = sample_meta.get("scientific_name") or "na"
    sample_alias = sample_meta.get("sample_alias") or sample_meta.get("sample_title") or sample_id
    hint_tokens = " ".join(
        filter(
            None,
            [
                sample_alias,
                sample_meta.get("description"),
                sample_meta.get("sample_title"),
                run_meta.get("library_name"),
            ],
        )
    ).lower()

    sample_type = "normal"
    if "tumour" in hint_tokens or "tumor" in hint_tokens:
        sample_type = "tumor"
    elif "blood" in hint_tokens:
        sample_type = "blood"

    row = {column: "na" for column in SAMPLE_COLUMNS}
    row.update(
        {
            "SAMPLEID": sample_id,
            "SAMPLESOURCE": scientific_name,
            "SAMPLECLASS": "research",
            "BIOLOGICAL_SEX": _normalise_sex(sample_meta.get("sex")),
            "CONCORDANCE_CONTROL_PATH": "na",
            "IS_POSITIVE_CONTROL": "false",
            "IS_NEGATIVE_CONTROL": "false",
            "SAMPLE_TYPE": sample_type,
            "TUM_NRM_SAMPLEID_MATCH": "na",
            "EXTERNAL_SAMPLE_ID": sample_alias,
            "TRUTH_DATA_DIR": "na",
            "N_X": "na",
            "N_Y": "na",
        }
    )
    return row


def write_tsv(path: Path, columns: Sequence[str], rows: Iterable[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({col: row.get(col, "") for col in columns})


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download ENA runs and build Daylily tables",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Example:
              bin/fetch_err_sources.py ERR1234567 ERR7654321
            """
        ),
    )
    parser.add_argument("err_uid", nargs="+", help="One or more ENA run accessions (ERR identifiers).")
    parser.add_argument(
        "--download-dir",
        default="resources/ena_runs",
        help="Directory to store downloaded data (default: resources/ena_runs).",
    )
    parser.add_argument(
        "--out-dir",
        default="conf",
        help="Directory for generated samples/units tables (default: conf).",
    )
    parser.add_argument(
        "--skip-download",
        action="store_true",
        help="Skip downloading files (useful for metadata-only dry runs).",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    run_records = _fetch_ena_records("read_run", args.err_uid, RUN_FIELDS, "run_accession")
    missing_runs = sorted(set(args.err_uid) - set(run_records))
    if missing_runs:
        raise EnaError(f"No metadata returned for: {', '.join(missing_runs)}")

    for run_id, meta in run_records.items():
        _ensure_even_fastq(run_id, meta)

    experiment_ids = [meta.get("experiment_accession", "") for meta in run_records.values()]
    experiment_records = _fetch_ena_records("experiment", experiment_ids, EXPERIMENT_FIELDS, "experiment_accession")

    sample_ids = [meta.get("sample_accession", "") for meta in run_records.values()]
    sample_records = _fetch_ena_records("sample", sample_ids, SAMPLE_FIELDS, "sample_accession")

    download_root = Path(args.download_dir)
    download_root.mkdir(parents=True, exist_ok=True)

    per_run_downloads: Dict[str, Tuple[str, List[Tuple[str, Path, str]]]] = {}
    for run_id, meta in run_records.items():
        download_type, plan = _plan_run_download(run_id, meta, download_root)
        per_run_downloads[run_id] = (download_type, plan)

    if not args.skip_download:
        for run_id, (download_type, plan) in per_run_downloads.items():
            for url, dest, md5 in plan:
                if dest.exists():
                    continue
                print(f"Downloading {run_id} ({download_type}): {url} -> {dest}")
                _download(url, dest, md5)

    units_rows: List[Dict[str, str]] = []
    sample_rows: Dict[str, Dict[str, str]] = {}

    for run_id, meta in run_records.items():
        download_type, plan = per_run_downloads[run_id]
        experiment_meta = experiment_records.get(meta.get("experiment_accession", ""), {})
        sample_meta = sample_records.get(meta.get("sample_accession", ""), {})

        units_rows.append(build_units_row(meta, experiment_meta, download_type, plan))

        sample_id = meta.get("sample_accession", "")
        if sample_id and sample_id not in sample_rows:
            sample_rows[sample_id] = build_sample_row(sample_id, meta, sample_meta)

    timestamp = _dt.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    out_dir = Path(args.out_dir)
    units_path = out_dir / f"err_source_{timestamp}_units.tsv"
    samples_path = out_dir / f"err_source_{timestamp}_samples.tsv"

    write_tsv(units_path, UNIT_COLUMNS, units_rows)
    write_tsv(samples_path, SAMPLE_COLUMNS, sample_rows.values())

    print(f"Wrote units table to: {units_path}")
    print(f"Wrote samples table to: {samples_path}")

    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    try:
        sys.exit(main())
    except EnaError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
