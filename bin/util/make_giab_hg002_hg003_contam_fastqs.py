#!/usr/bin/env python3
"""Build deterministic GIAB FASTQs with synthetic GIAB contamination.

The default inputs are the GIAB Illumina NovaSeqX HG002 and HG003 30x FASTQs on
the Daylily headnode. For each requested contamination level, the script samples
the primary dataset to the remaining primary fraction and the donor dataset to
the donor fraction needed for an approximately constant target coverage.
"""

import argparse
import csv
import random
import shlex
import shutil
import subprocess
import sys
from decimal import Decimal, InvalidOperation, getcontext
from pathlib import Path

getcontext().prec = 28

DEFAULT_LEVELS = "0.1,0.5,1,2,3,4,5,10,20,30"
CONTAMINATION_LEVELS_PCT = [0.1, 0.5, 1, 2, 3, 4, 5, 10, 20, 30]
DEFAULT_PRIMARY_SAMPLE = "HG002"
DEFAULT_DONOR_SAMPLE = "HG003"
DEFAULT_OUT_DIR = "/fsx/scratch/dayoa_qc_contam/giab_hg002_hg003_5x_20260425"
DEFAULT_READ_ROOT = "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/NovaSeqX_WHGS_TruSeqPF_HG002-007"
DEFAULT_TRUTH_DIR = "/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/snv/v4.2.1/HG002/"

SAMPLES_HEADER = [
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

UNITS_HEADER = [
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


def default_path(name):
    return str(Path(DEFAULT_READ_ROOT) / name)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "Create paired GIAB synthetic contamination FASTQs and "
            "Daylily samples.tsv/units.tsv manifests."
        )
    )
    parser.add_argument("--output-dir", default=DEFAULT_OUT_DIR)
    parser.add_argument("--levels", default=DEFAULT_LEVELS)
    parser.add_argument("--target-coverage", default="5")
    parser.add_argument("--primary-sample", default=DEFAULT_PRIMARY_SAMPLE)
    parser.add_argument("--donor-sample", default=DEFAULT_DONOR_SAMPLE)
    parser.add_argument("--primary-coverage", default="30")
    parser.add_argument("--donor-coverage", default="30")
    parser.add_argument(
        "--primary-r1",
        default=None,
    )
    parser.add_argument(
        "--primary-r2",
        default=None,
    )
    parser.add_argument("--donor-r1", default=None)
    parser.add_argument("--donor-r2", default=None)
    parser.add_argument("--truth-dir", default=DEFAULT_TRUTH_DIR)
    parser.add_argument("--threads", type=int, default=16)
    parser.add_argument("--primary-seed", type=int, default=20260425)
    parser.add_argument("--donor-seed", type=int, default=20260426)
    parser.add_argument("--run-id", default="GIABCONTAM20260425")
    parser.add_argument("--sample-prefix", default=None)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--keep-components", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.primary_r1 is None:
        args.primary_r1 = default_path(f"{args.primary_sample}_30x_R1.fastq.gz")
    if args.primary_r2 is None:
        args.primary_r2 = default_path(f"{args.primary_sample}_30x_R2.fastq.gz")
    if args.donor_r1 is None:
        args.donor_r1 = default_path(f"{args.donor_sample}_30x_R1.fastq.gz")
    if args.donor_r2 is None:
        args.donor_r2 = default_path(f"{args.donor_sample}_30x_R2.fastq.gz")
    if args.sample_prefix is None:
        args.sample_prefix = f"{args.primary_sample}-{args.donor_sample}-contam"
    return args


def decimal_arg(value, name):
    try:
        parsed = Decimal(str(value))
    except InvalidOperation as exc:
        raise ValueError(f"{name} must be numeric: {value}") from exc
    if parsed <= 0:
        raise ValueError(f"{name} must be greater than zero: {value}")
    return parsed


def parse_levels(levels_text):
    levels = []
    for raw in levels_text.split(","):
        item = raw.strip()
        if not item:
            continue
        level = decimal_arg(item, "contamination level")
        if level >= 100:
            raise ValueError(f"contamination level must be less than 100: {item}")
        levels.append(level)
    if not levels:
        raise ValueError("at least one contamination level is required")
    return levels


def calculate_mix_counts(total_read_pairs, contamination_pct):
    total = int(total_read_pairs)
    if total <= 0:
        raise ValueError("total_read_pairs must be greater than zero")
    pct = decimal_arg(contamination_pct, "contamination_pct")
    if pct >= 100:
        raise ValueError("contamination_pct must be less than 100")
    donor = int((Decimal(total) * pct / Decimal("100")).to_integral_value())
    return {
        "total_read_pairs": total,
        "primary_read_pairs": total - donor,
        "donor_read_pairs": donor,
    }


def fmt_decimal(value):
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def fmt_fraction(value):
    return f"{value:.12f}".rstrip("0").rstrip(".")


def level_label(level):
    return fmt_decimal(level).replace(".", "p") + "pct"


def contamination_sample_id(primary_sample, donor_sample, level):
    return f"{primary_sample}-{donor_sample}-contam-{level_label(Decimal(str(level)))}"


def require_tool(name):
    path = shutil.which(name)
    if path is None:
        raise FileNotFoundError(f"required tool not found on PATH: {name}")
    return path


def require_file(path_text):
    path = Path(path_text).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"required input FASTQ is missing: {path}")
    return path


def abs_output_dir(path_text):
    path = Path(path_text).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    return path


def build_plan(args):
    levels = parse_levels(args.levels)
    target_cov = decimal_arg(args.target_coverage, "target coverage")
    primary_cov = decimal_arg(args.primary_coverage, "primary coverage")
    donor_cov = decimal_arg(args.donor_coverage, "donor coverage")
    out_dir = abs_output_dir(args.output_dir)
    fastq_dir = out_dir / "fastqs"
    tmp_dir = out_dir / ".tmp_components"
    rows = []

    for index, level in enumerate(levels, start=1):
        contam_fraction = level / Decimal("100")
        primary_fraction = target_cov * (Decimal("1") - contam_fraction) / primary_cov
        donor_fraction = target_cov * contam_fraction / donor_cov
        if primary_fraction <= 0 or primary_fraction > 1:
            raise ValueError(
                "primary sampling fraction is outside (0, 1]: "
                f"level={fmt_decimal(level)} pct fraction={fmt_fraction(primary_fraction)}"
            )
        if donor_fraction <= 0 or donor_fraction > 1:
            raise ValueError(
                "donor sampling fraction is outside (0, 1]: "
                f"level={fmt_decimal(level)} pct fraction={fmt_fraction(donor_fraction)}"
            )

        label = level_label(level)
        sample_id = f"{args.sample_prefix}-{label}"
        rows.append(
            {
                "index": index,
                "level": level,
                "label": label,
                "sample_id": sample_id,
                "primary_fraction": primary_fraction,
                "donor_fraction": donor_fraction,
                "r1": fastq_dir / f"{sample_id}_R1.fastq.gz",
                "r2": fastq_dir / f"{sample_id}_R2.fastq.gz",
                "tmp": tmp_dir / label,
            }
        )
    return out_dir, rows


def build_manifest_rows(
    output_root,
    primary_sample="HG002",
    donor_sample="HG003",
    levels_pct=None,
    truth_dir=DEFAULT_TRUTH_DIR,
):
    out_dir = Path(output_root)
    levels = levels_pct or CONTAMINATION_LEVELS_PCT
    samples = []
    units = []
    expected = []
    for index, level in enumerate(levels, start=1):
        level_dec = Decimal(str(level))
        sample_id = contamination_sample_id(primary_sample, donor_sample, level_dec)
        r1 = out_dir / "fastqs" / f"{sample_id}_R1.fastq.gz"
        r2 = out_dir / "fastqs" / f"{sample_id}_R2.fastq.gz"
        samples.append(
            {
                "SAMPLEID": sample_id,
                "SAMPLESOURCE": "blood",
                "SAMPLECLASS": "research",
                "BIOLOGICAL_SEX": "male",
                "CONCORDANCE_CONTROL_PATH": truth_dir,
                "IS_POSITIVE_CONTROL": "true",
                "IS_NEGATIVE_CONTROL": "false",
                "SAMPLE_TYPE": "gdna",
                "TUM_NRM_SAMPLEID_MATCH": "",
                "EXTERNAL_SAMPLE_ID": primary_sample,
                "N_X": "1",
                "N_Y": "1",
                "TRUTH_DATA_DIR": truth_dir,
            }
        )
        unit = {field: "" for field in UNITS_HEADER}
        unit.update(
            {
                "RUNID": "GIABCONTAM20260425",
                "SAMPLEID": sample_id,
                "EXPERIMENTID": f"{primary_sample}-5x-{donor_sample}-{level_label(level_dec)}",
                "LANEID": str(index),
                "BARCODEID": "D0",
                "LIBPREP": "PCR-FREE",
                "SEQ_VENDOR": "ILMN",
                "SEQ_PLATFORM": "NOVASEQ",
                "ILMN_R1_PATH": str(r1),
                "ILMN_R2_PATH": str(r2),
                "SUBSAMPLE_PCT": "na",
                "SAMPLEUSE": "posControl",
                "BWA_KMER": "19",
                "DEEP_MODEL": "WGS",
            }
        )
        units.append(unit)
        expected.append(
            {
                "SAMPLEID": sample_id,
                "EXPECTED_CONTAMINATION_PCT": fmt_decimal(level_dec),
                "PRIMARY_SAMPLE": primary_sample,
                "DONOR_SAMPLE": donor_sample,
                "DONOR_ILMN_R1_PATH": default_path(f"{donor_sample}_30x_R1.fastq.gz"),
                "DONOR_ILMN_R2_PATH": default_path(f"{donor_sample}_30x_R2.fastq.gz"),
            }
        )
    return {
        "samples": samples,
        "units": units,
        "expected_contamination": expected,
    }


def check_expected_outputs(out_dir, rows, force):
    expected = [
        out_dir / "samples.tsv",
        out_dir / "units.tsv",
        out_dir / "contamination_plan.tsv",
    ]
    for row in rows:
        expected.extend([row["r1"], row["r2"]])
    present = [path for path in expected if path.exists()]
    if present and not force:
        joined = "\n".join(f"  {path}" for path in present)
        raise FileExistsError(
            "refusing to overwrite existing generated outputs; pass --force to replace:\n"
            + joined
        )


def run_cmd(argv, dry_run):
    print("+ " + shlex.join([str(part) for part in argv]), flush=True)
    if dry_run:
        return
    subprocess.run([str(part) for part in argv], check=True)


def read_fastq_record(handle, source):
    lines = [handle.readline() for _ in range(4)]
    if not lines[0]:
        if any(lines[1:]):
            raise RuntimeError(f"truncated FASTQ record at end of {source}")
        return None
    if any(not line for line in lines[1:]):
        raise RuntimeError(f"truncated FASTQ record in {source}")
    return b"".join(lines)


def open_pigz_reader(path):
    return subprocess.Popen(
        ["pigz", "-dc", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def open_pigz_writer(path, mode, threads):
    path.parent.mkdir(parents=True, exist_ok=True)
    out_handle = path.open(mode)
    proc = subprocess.Popen(
        ["pigz", "-p", str(threads), "-c"],
        stdin=subprocess.PIPE,
        stdout=out_handle,
        stderr=subprocess.PIPE,
    )
    return proc, out_handle


def close_writer(proc, handle, label):
    if proc.stdin is not None:
        proc.stdin.close()
    stderr = proc.stderr.read().decode("utf-8", errors="replace") if proc.stderr else ""
    rc = proc.wait()
    handle.close()
    if rc != 0:
        raise subprocess.CalledProcessError(rc, f"pigz writer for {label}", stderr=stderr)


def close_reader(proc, label):
    stderr = proc.stderr.read().decode("utf-8", errors="replace") if proc.stderr else ""
    rc = proc.wait()
    if rc != 0:
        raise subprocess.CalledProcessError(rc, f"pigz reader for {label}", stderr=stderr)


def write_records_to_matching_outputs(record_r1, record_r2, rows, random_value, writers, fraction_key):
    kept = 0
    for row in rows:
        if random_value >= float(row[fraction_key]):
            continue
        writer_r1, writer_r2 = writers[row["label"]]
        writer_r1.stdin.write(record_r1)
        writer_r2.stdin.write(record_r2)
        kept += 1
    return kept


def stream_sample_source(source_name, r1_path, r2_path, rows, fraction_key, seed, threads, append):
    mode = "ab" if append else "wb"
    writer_threads = max(1, min(threads, 2))
    print(
        "+ stream paired FASTQs with deterministic sampling: "
        f"{source_name} seed={seed} writer_threads={writer_threads}",
        flush=True,
    )
    writers = {}
    active_writers = {}
    for row in rows:
        proc_r1, handle_r1 = open_pigz_writer(row["r1"], mode, writer_threads)
        proc_r2, handle_r2 = open_pigz_writer(row["r2"], mode, writer_threads)
        writers[row["label"]] = (proc_r1, proc_r2, handle_r1, handle_r2)
        active_writers[row["label"]] = (proc_r1, proc_r2)

    reader_r1 = open_pigz_reader(r1_path)
    reader_r2 = open_pigz_reader(r2_path)
    rng = random.Random(seed)
    processed = 0
    kept_writes = 0
    try:
        if reader_r1.stdout is None or reader_r2.stdout is None:
            raise RuntimeError("pigz reader did not expose stdout")
        while True:
            record_r1 = read_fastq_record(reader_r1.stdout, r1_path)
            record_r2 = read_fastq_record(reader_r2.stdout, r2_path)
            if record_r1 is None and record_r2 is None:
                break
            if record_r1 is None or record_r2 is None:
                raise RuntimeError(f"paired FASTQs have different record counts: {source_name}")
            processed += 1
            kept_writes += write_records_to_matching_outputs(
                record_r1,
                record_r2,
                rows,
                rng.random(),
                active_writers,
                fraction_key,
            )
            if processed % 5_000_000 == 0:
                print(
                    f"{source_name}: processed {processed} read pairs; "
                    f"output writes={kept_writes}",
                    flush=True,
                )
    finally:
        for label, (proc_r1, proc_r2, handle_r1, handle_r2) in writers.items():
            close_writer(proc_r1, handle_r1, f"{label} R1")
            close_writer(proc_r2, handle_r2, f"{label} R2")
        close_reader(reader_r1, f"{source_name} R1")
        close_reader(reader_r2, f"{source_name} R2")
    print(
        f"{source_name}: processed {processed} read pairs; output writes={kept_writes}",
        flush=True,
    )


def require_nonempty(path):
    if not path.is_file():
        raise FileNotFoundError(f"expected output was not created: {path}")
    if path.stat().st_size == 0:
        raise RuntimeError(f"expected output is empty: {path}")


def generate_fastqs(args, rows, primary_r1, primary_r2, donor_r1, donor_r2):
    for row in rows:
        print(
            "Building "
            f"{row['sample_id']} "
            f"({fmt_decimal(row['level'])}% {args.donor_sample} donor)",
            flush=True,
        )
        if args.dry_run:
            print(
                "+ would stream primary and donor paired FASTQs into "
                f"{row['r1']} and {row['r2']}",
                flush=True,
            )
    if args.dry_run:
        return
    stream_sample_source(
        f"{args.primary_sample} primary",
        primary_r1,
        primary_r2,
        rows,
        "primary_fraction",
        args.primary_seed,
        args.threads,
        append=False,
    )
    stream_sample_source(
        f"{args.donor_sample} donor",
        donor_r1,
        donor_r2,
        rows,
        "donor_fraction",
        args.donor_seed,
        args.threads,
        append=True,
    )
    for row in rows:
        if not args.dry_run:
            require_nonempty(row["r1"])
            require_nonempty(row["r2"])


def write_tsv(path, header, rows):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=header,
            delimiter="\t",
            lineterminator="\n",
            extrasaction="ignore",
        )
        writer.writeheader()
        writer.writerows(rows)


def write_manifests(args, out_dir, rows, primary_r1, primary_r2, donor_r1, donor_r2):
    if args.dry_run:
        print("Dry run: not writing manifests.", flush=True)
        return
    samples = []
    units = []
    plan = []
    for row in rows:
        samples.append(
            {
                "SAMPLEID": row["sample_id"],
                "SAMPLESOURCE": "blood",
                "SAMPLECLASS": "research",
                "BIOLOGICAL_SEX": "male",
                "CONCORDANCE_CONTROL_PATH": args.truth_dir,
                "IS_POSITIVE_CONTROL": "true",
                "IS_NEGATIVE_CONTROL": "false",
                "SAMPLE_TYPE": "gdna",
                "TUM_NRM_SAMPLEID_MATCH": "",
                "EXTERNAL_SAMPLE_ID": args.primary_sample,
                "N_X": "1",
                "N_Y": "1",
                "TRUTH_DATA_DIR": args.truth_dir,
            }
        )
        units.append(
            {
                "RUNID": args.run_id,
                "SAMPLEID": row["sample_id"],
                "EXPERIMENTID": f"{args.primary_sample}-5x-{args.donor_sample}-{row['label']}",
                "LANEID": str(row["index"]),
                "BARCODEID": "D0",
                "LIBPREP": "PCR-FREE",
                "SEQ_VENDOR": "ILMN",
                "SEQ_PLATFORM": "NOVASEQ",
                "ILMN_R1_PATH": str(row["r1"]),
                "ILMN_R2_PATH": str(row["r2"]),
                "SAMPLEUSE": "posControl",
                "BWA_KMER": "19",
                "DEEP_MODEL": "WGS",
            }
        )
        plan.append(
            {
                "sample_id": row["sample_id"],
                "contamination_percent": fmt_decimal(row["level"]),
                "target_coverage": args.target_coverage,
                "primary_sample": args.primary_sample,
                "primary_r1": str(primary_r1),
                "primary_r2": str(primary_r2),
                "primary_coverage": args.primary_coverage,
                "primary_sampling_fraction": fmt_fraction(row["primary_fraction"]),
                "primary_seed": str(args.primary_seed),
                "donor_sample": args.donor_sample,
                "donor_r1": str(donor_r1),
                "donor_r2": str(donor_r2),
                "donor_coverage": args.donor_coverage,
                "donor_sampling_fraction": fmt_fraction(row["donor_fraction"]),
                "donor_seed": str(args.donor_seed),
                "output_r1": str(row["r1"]),
                "output_r2": str(row["r2"]),
            }
        )

    empty_unit_fields = {key: "" for key in UNITS_HEADER}
    full_units = []
    for row in units:
        merged = empty_unit_fields.copy()
        merged.update(row)
        full_units.append(merged)

    out_dir.mkdir(parents=True, exist_ok=True)
    write_tsv(out_dir / "samples.tsv", SAMPLES_HEADER, samples)
    write_tsv(out_dir / "units.tsv", UNITS_HEADER, full_units)
    write_tsv(out_dir / "contamination_plan.tsv", list(plan[0].keys()), plan)
    print(f"Wrote {out_dir / 'samples.tsv'}", flush=True)
    print(f"Wrote {out_dir / 'units.tsv'}", flush=True)
    print(f"Wrote {out_dir / 'contamination_plan.tsv'}", flush=True)


def main():
    args = parse_args()
    if args.threads < 1:
        raise ValueError("--threads must be at least 1")

    require_tool("pigz")
    primary_r1 = require_file(args.primary_r1)
    primary_r2 = require_file(args.primary_r2)
    donor_r1 = require_file(args.donor_r1)
    donor_r2 = require_file(args.donor_r2)
    out_dir, rows = build_plan(args)
    if not args.dry_run:
        check_expected_outputs(out_dir, rows, args.force)

    print(f"Output directory: {out_dir}", flush=True)
    print(f"Contamination levels: {args.levels}", flush=True)
    print(f"Target coverage: {args.target_coverage}x", flush=True)
    generate_fastqs(args, rows, primary_r1, primary_r2, donor_r1, donor_r2)
    write_manifests(args, out_dir, rows, primary_r1, primary_r2, donor_r1, donor_r2)
    print("Done.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
