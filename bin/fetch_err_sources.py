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

# removed cram_ftp,cram_md5,cram_bytes,cram_index_ftp

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import datetime as _dt
import hashlib
import io
import os
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
import sys
import textwrap
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, Iterable, List, Literal, Sequence

ENA_FILEREPORT_URL = "https://www.ebi.ac.uk/ena/portal/api/filereport"
BODY_PREVIEW_CHARS = 600

# OK

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
    "bam_ftp",
    "bam_md5",
    "bam_bytes",
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


@dataclass
class DownloadItem:
    url: str
    destination: Path
    md5: str | None = None
    size: int | None = None


@dataclass
class RunDownloadPlan:
    download_type: Literal["fastq", "cram", "bam"]
    downloads: List[DownloadItem] = field(default_factory=list)
    fastq_outputs: List[Path] = field(default_factory=list)
    conversion_command: List[str] | None = None
    conversion_tempdir: Path | None = None


class EnaError(RuntimeError):
    """Raised when the ENA API cannot satisfy a request."""


def _http_get(url: str) -> str:
    print(f"Fetching URL: {url}")
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
    seen: set[str] = set()
    unique: List[str] = []
    for accession in accessions:
        if not accession or accession in seen:
            continue
        unique.append(accession)
        seen.add(accession)
    if not unique:
        return {}
    params: List[tuple[str, str]] = [
        ("result", result),
        ("format", "tsv"),
        ("limit", "0"),
    ]
    params.extend(("accession", accession) for accession in unique)
    url = f"{ENA_FILEREPORT_URL}?{urllib.parse.urlencode(params)}"
    text = _http_get(url)
    if not text.strip():
        return {}
    reader = csv.DictReader(io.StringIO(text), delimiter="\t")
    records: Dict[str, Dict[str, str]] = {}
    for row in reader:
        key = (row.get(key_field) or "").strip()
        if key:
            cleaned = {k: (v or "").strip() for k, v in row.items() if k}
            if fields:
                records[key] = {field: cleaned.get(field, "") for field in fields}
            else:
                records[key] = cleaned
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


def _resolve_sample_id(run_meta: Dict[str, str]) -> str:
    for key in ("sample_accession", "sample_alias", "sample_title", "run_accession"):
        value = (run_meta.get(key) or "").strip()
        if value:
            return value
    return (run_meta.get("run_accession") or "").strip()


def _check_fastq_pairing(run_id: str, run_meta: Dict[str, str]) -> tuple[bool, str]:
    layout = (run_meta.get("library_layout") or "").strip().upper()
    fastq_files = _split_values(run_meta.get("fastq_ftp", ""))
    if layout == "SINGLE":
        return False, "Run {run} is single-end; paired FASTQ data is required.".format(
            run=run_id
        )
    if fastq_files and len(fastq_files) % 2 != 0:
        return False, "Run {run} reports an odd number of FASTQ files: {files}".format(
            run=run_id, files=fastq_files
        )
    return True, ""


def _md5(path: Path) -> str:
    hash_md5 = hashlib.md5()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8192), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def _download(url: str, destination: Path, expected_md5: str | None = None) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, destination.open(
        "wb"
    ) as handle:  # pragma: no cover - network
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
    fasterq_dump: str | None,
    *,
    leave_ena_formatted_readnames: bool,
) -> RunDownloadPlan:
    fastq_files = _split_values(run_meta.get("fastq_ftp", ""))
    fastq_md5 = _split_values(run_meta.get("fastq_md5", ""))
    bam_files = _split_values(run_meta.get("bam_ftp", ""))
    bam_md5 = _split_values(run_meta.get("bam_md5", ""))
    fastq_sizes_raw = _split_values(run_meta.get("fastq_bytes", ""))
    submitted_sizes_raw = _split_values(run_meta.get("submitted_bytes", ""))
    bam_sizes_raw = _split_values(run_meta.get("bam_bytes", ""))
    submitted_files = _split_values(run_meta.get("submitted_ftp", ""))
    submitted_md5 = _split_values(run_meta.get("submitted_md5", ""))
    submitted_formats = [
        value.lower() for value in _split_values(run_meta.get("submitted_format", ""))
    ]

    target_dir = download_dir / run_id

    if fastq_files:
        if len(fastq_files) < 2:
            raise EnaError(
                f"Run {run_id} does not provide a complete paired FASTQ set."
            )
        downloads: List[DownloadItem] = []
        for idx, remote in enumerate(fastq_files):
            dest = target_dir / Path(remote).name
            md5 = fastq_md5[idx] if idx < len(fastq_md5) else None
            size = None
            if idx < len(fastq_sizes_raw):
                try:
                    size = int(fastq_sizes_raw[idx])
                except ValueError:
                    size = None
            downloads.append(DownloadItem(_normalise_remote(remote), dest, md5, size))
        fastq_outputs = [item.destination for item in downloads[:2]]
        return RunDownloadPlan(
            "fastq", downloads=downloads, fastq_outputs=fastq_outputs
        )

    submitted_entries: List[tuple[str, str, str | None]] = []
    for idx, remote in enumerate(submitted_files):
        fmt = submitted_formats[idx] if idx < len(submitted_formats) else ""
        md5 = submitted_md5[idx] if idx < len(submitted_md5) else None
        size = None
        if idx < len(submitted_sizes_raw):
            try:
                size = int(submitted_sizes_raw[idx])
            except ValueError:
                size = None
        submitted_entries.append((remote, fmt, md5, size))

    def _make_download(remote: str, md5: str | None, size: int | None) -> DownloadItem:
        return DownloadItem(
            _normalise_remote(remote), target_dir / Path(remote).name, md5, size
        )

    submitted_fastqs = [
        _make_download(remote, md5, size)
        for remote, fmt, md5, size in submitted_entries
        if fmt.startswith("fastq")
        or remote.lower().endswith((".fastq", ".fastq.gz", ".fq", ".fq.gz"))
    ]
    if submitted_fastqs:
        if len(submitted_fastqs) < 2:
            raise EnaError(
                f"Run {run_id} does not provide a complete paired FASTQ set."
            )
        return RunDownloadPlan(
            "fastq",
            downloads=submitted_fastqs,
            fastq_outputs=[download.destination for download in submitted_fastqs[:2]],
        )

    for remote, fmt, md5, size in submitted_entries:
        if fmt == "sra" or remote.lower().endswith(".sra"):
            if not fasterq_dump:
                raise EnaError(
                    f"Run {run_id} only provides SRA archives but the SRA Toolkit (fasterq-dump)"
                    " is not available."
                )
            download = _make_download(remote, md5, size)
            base_name = Path(download.destination).stem
            fastq_outputs = [
                target_dir / f"{base_name}_1.fastq",
                target_dir / f"{base_name}_2.fastq",
            ]
            conversion_command = [
                fasterq_dump,
                "--split-files",
                "--outdir",
                str(target_dir),
                "--temp",
                str(target_dir / "tmp"),
            ]
            if not leave_ena_formatted_readnames:
                conversion_command.extend(
                    [
                        "--defline-seq",
                        "@$sn/$ri",
                        "--defline-qual",
                        "+",
                    ]
                )
            conversion_command.append(str(download.destination))
            plan = RunDownloadPlan(
                "fastq",
                downloads=[download],
                fastq_outputs=fastq_outputs,
                conversion_command=conversion_command,
                conversion_tempdir=target_dir / "tmp",
            )
            return plan

    for remote, fmt, md5, size in submitted_entries:
        if fmt == "cram" or remote.lower().endswith(".cram"):
            download = _make_download(remote, md5, size)
            return RunDownloadPlan("cram", downloads=[download])

    if bam_files:
        downloads: List[DownloadItem] = []
        for idx, remote in enumerate(bam_files):
            dest = target_dir / Path(remote).name
            md5 = bam_md5[idx] if idx < len(bam_md5) else None
            size = None
            if idx < len(bam_sizes_raw):
                try:
                    size = int(bam_sizes_raw[idx])
                except ValueError:
                    size = None
            downloads.append(DownloadItem(_normalise_remote(remote), dest, md5, size))
        return RunDownloadPlan("bam", downloads=downloads)

    for remote, fmt, md5, size in submitted_entries:
        if fmt == "bam" or remote.lower().endswith(".bam"):
            download = _make_download(remote, md5, size)
            return RunDownloadPlan("bam", downloads=[download])

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
    plan: RunDownloadPlan,
) -> Dict[str, str]:
    row = {column: "" for column in UNIT_COLUMNS}

    run_id = run_meta.get("run_accession", "")
    sample_id = _resolve_sample_id(run_meta)
    experiment_id = run_meta.get("experiment_accession", "")
    instrument = (
        run_meta.get("instrument_platform")
        or run_meta.get("instrument_model")
        or "UNKNOWN"
    )
    libprep = (
        run_meta.get("library_selection")
        or run_meta.get("library_strategy")
        or "UNKNOWN"
    )
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

    if plan.download_type == "fastq":
        if len(plan.fastq_outputs) >= 2:
            row["ILMN_R1_PATH"] = str(plan.fastq_outputs[0])
            row["ILMN_R2_PATH"] = str(plan.fastq_outputs[1])
        # Clear cram/bam columns
        row["ULTIMA_CRAM"] = ""
        row["ONT_CRAM"] = ""
        row["PB_BAM"] = ""
    elif plan.download_type == "cram":
        cram_path = str(plan.downloads[0].destination)
        row["ULTIMA_CRAM"] = cram_path
        row["ONT_CRAM"] = cram_path if "ONT" in instrument.upper() else ""
        row["PB_BAM"] = ""
    elif plan.download_type == "bam":
        bam_path = str(plan.downloads[0].destination)
        row["PB_BAM"] = bam_path
        row["ULTIMA_CRAM"] = ""
        row["ONT_CRAM"] = ""
    else:
        raise ValueError(f"Unsupported download type: {plan.download_type}")

    return row


def build_sample_row(
    sample_id: str,
    run_meta: Dict[str, str],
    sample_meta: Dict[str, str],
) -> Dict[str, str]:
    scientific_name = sample_meta.get("scientific_name") or "na"
    sample_alias = (
        sample_meta.get("sample_alias") or sample_meta.get("sample_title") or sample_id
    )
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


def write_tsv(
    path: Path, columns: Sequence[str], rows: Iterable[Dict[str, str]]
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=columns, delimiter="\t", lineterminator="\n"
        )
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
    parser.add_argument(
        "err_uid", nargs="+", help="One or more ENA run accessions (ERR identifiers)."
    )
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
    parser.add_argument(
        "--skip-singletons",
        action="store_true",
        help="Skip runs that do not provide paired FASTQ files, logging the skipped runs.",
    )
    overwrite_group = parser.add_mutually_exclusive_group()
    overwrite_group.add_argument(
        "--overwrite",
        action="store_true",
        help=(
            "Overwrite any existing downloaded files for the requested runs before"
            " downloading."
        ),
    )
    overwrite_group.add_argument(
        "--skip-existing",
        action="store_true",
        help=(
            "Do not overwrite existing downloaded files; emit a warning when they"
            " are detected."
        ),
    )
    parser.add_argument(
        "--check-existing",
        action="store_true",
        help=(
            "Report whether existing downloaded files match the expected sizes"
            " before any downloads are attempted."
        ),
    )
    parser.add_argument(
        "--leave-ena-formatted-readnames",
        action="store_true",
        help=(
            "Keep the ENA-formatted read names emitted by fasterq-dump instead of"
            " normalising them to Illumina-style deflines."
        ),
    )
    parser.add_argument(
        "--parallel",
        type=int,
        default=1,
        help="Number of concurrent downloads to perform (default: 1).",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if args.parallel < 1:
        raise EnaError("--parallel must be at least 1.")

    cpu_count = os.cpu_count() or 1
    if args.parallel > cpu_count:
        print(
            "WARNING: --parallel value {parallel} exceeds available processors ({nproc}).".format(
                parallel=args.parallel, nproc=cpu_count
            ),
            file=sys.stderr,
        )

    timestamp = _dt.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    requested_runs: List[str] = []
    seen_runs: set[str] = set()
    duplicate_runs: List[str] = []
    for run in args.err_uid:
        if run in seen_runs:
            duplicate_runs.append(run)
            continue
        seen_runs.add(run)
        requested_runs.append(run)

    if duplicate_runs:
        raise EnaError(
            "Duplicate run accessions supplied: {runs}".format(
                runs=", ".join(sorted(set(duplicate_runs)))
            )
        )

    run_records = _fetch_ena_records(
        "read_run", requested_runs, RUN_FIELDS, "run_accession"
    )
    missing_runs = sorted(set(requested_runs) - set(run_records))
    if missing_runs:
        raise EnaError(f"No metadata returned for: {', '.join(missing_runs)}")

    singleton_messages: List[str] = []
    filtered_runs: Dict[str, Dict[str, str]] = {}
    for run_id, meta in run_records.items():
        ok, reason = _check_fastq_pairing(run_id, meta)
        if ok:
            filtered_runs[run_id] = meta
            continue
        if args.skip_singletons:
            warning = f"WARNING: {reason} Skipping run."
            print(warning, file=sys.stderr)
            singleton_messages.append(f"{run_id}\t{reason}")
            continue
        raise EnaError(reason)

    run_records = filtered_runs

    experiment_ids = [
        meta.get("experiment_accession", "") for meta in run_records.values()
    ]
    experiment_records = _fetch_ena_records(
        "experiment", experiment_ids, EXPERIMENT_FIELDS, "experiment_accession"
    )

    sample_ids = [meta.get("sample_accession", "") for meta in run_records.values()]
    sample_records = _fetch_ena_records(
        "sample", sample_ids, SAMPLE_FIELDS, "sample_accession"
    )

    download_root = Path(args.download_dir)
    download_root.mkdir(parents=True, exist_ok=True)

    fasterq_dump = shutil.which("fasterq-dump")

    per_run_downloads: Dict[str, RunDownloadPlan] = {}
    for run_id, meta in run_records.items():
        plan = _plan_run_download(
            run_id,
            meta,
            download_root,
            fasterq_dump,
            leave_ena_formatted_readnames=args.leave_ena_formatted_readnames,
        )
        per_run_downloads[run_id] = plan

    for run_id, plan in per_run_downloads.items():
        existing_items: List[tuple[DownloadItem, int]] = []
        for item in plan.downloads:
            if item.destination.exists():
                actual_size = item.destination.stat().st_size
                existing_items.append((item, actual_size))
                if args.check_existing:
                    if item.size is None:
                        message = (
                            f"Existing file for {run_id}: {item.destination} "
                            f"has size {actual_size} bytes (expected size unknown)."
                        )
                    elif actual_size == item.size:
                        message = (
                            f"Existing file for {run_id}: {item.destination} "
                            f"matches expected size {item.size} bytes."
                        )
                    else:
                        message = (
                            f"Existing file for {run_id}: {item.destination} "
                            f"has size {actual_size} bytes (expected {item.size})."
                        )
                    print(f"CHECK: {message}")
        if not existing_items:
            continue
        if args.skip_existing:
            print(
                "WARNING: Existing files detected for run {run}; skipping download"
                " (--skip-existing).".format(run=run_id),
                file=sys.stderr,
            )
            for item, actual_size in existing_items:
                if item.size is not None and actual_size != item.size:
                    raise EnaError(
                        "Existing file for run {run} has unexpected size ({actual} bytes,"
                        " expected {expected}). Re-run with --overwrite to replace it.".format(
                            run=run_id, actual=actual_size, expected=item.size
                        )
                    )
            continue
        if args.overwrite:
            for item, _ in existing_items:
                try:
                    item.destination.unlink()
                except FileNotFoundError:
                    pass
            continue
        conflict_paths = ", ".join(str(item.destination) for item, _ in existing_items)
        raise EnaError(
            "Existing files found for run {run}: {paths}. Use --overwrite or"
            " --skip-existing to proceed.".format(run=run_id, paths=conflict_paths)
        )

    if not args.skip_download:
        download_queue: List[tuple[str, RunDownloadPlan, DownloadItem]] = []
        for run_id, plan in per_run_downloads.items():
            for item in plan.downloads:
                if item.destination.exists():
                    continue
                print(
                    f"Downloading {run_id} ({plan.download_type}): {item.url} -> {item.destination}"
                )
                download_queue.append((run_id, plan, item))

        if download_queue:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=args.parallel
            ) as executor:
                futures = [
                    executor.submit(_download, item.url, item.destination, item.md5)
                    for _, _, item in download_queue
                ]
                for future in concurrent.futures.as_completed(futures):
                    future.result()

        for run_id, plan in per_run_downloads.items():
            if plan.conversion_command:
                outputs_ready = plan.fastq_outputs and all(
                    path.exists() for path in plan.fastq_outputs
                )
                if outputs_ready:
                    continue
                if plan.conversion_tempdir is not None:
                    plan.conversion_tempdir.mkdir(parents=True, exist_ok=True)
                print(
                    "Converting {run_id} SRA to FASTQ via fasterq-dump: {command}".format(
                        run_id=run_id, command=" ".join(plan.conversion_command)
                    )
                )
                try:
                    subprocess.run(plan.conversion_command, check=True)
                except subprocess.CalledProcessError as exc:
                    raise EnaError(
                        f"fasterq-dump failed for run {run_id} with exit code {exc.returncode}."
                    ) from exc

    units_rows: List[Dict[str, str]] = []
    sample_rows: Dict[str, Dict[str, str]] = {}

    for run_id, meta in run_records.items():
        plan = per_run_downloads[run_id]
        experiment_meta = experiment_records.get(
            meta.get("experiment_accession", ""), {}
        )
        sample_meta = sample_records.get(meta.get("sample_accession", ""), {})

        units_rows.append(build_units_row(meta, experiment_meta, plan))

        sample_id = _resolve_sample_id(meta)
        if sample_id and sample_id not in sample_rows:
            sample_rows[sample_id] = build_sample_row(sample_id, meta, sample_meta)

    units_path = out_dir / f"err_source_{timestamp}_units.tsv"
    samples_path = out_dir / f"err_source_{timestamp}_samples.tsv"

    if singleton_messages:
        singleton_log = out_dir / f"err_singletons_{timestamp}.log"
        with singleton_log.open("w", encoding="utf-8") as handle:
            for entry in singleton_messages:
                handle.write(f"{entry}\n")
        print(f"Wrote singleton log to: {singleton_log}")

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
