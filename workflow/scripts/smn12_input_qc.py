#!/usr/bin/env python3
"""Preflight BAM/CRAM inputs for SMN12 callers."""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


FIELDNAMES_INPUT_QC = [
    "sample",
    "aligner",
    "deduper",
    "input_path",
    "reference_path",
    "input_format",
    "quickcheck_status",
    "sq_count",
    "total_sq_bases",
    "input_scope",
    "read_group_count",
    "read_groups_json",
    "sample_names_json",
    "sampled_records",
    "sampled_mapped_records",
    "sampled_primary_records",
    "sampled_duplicate_records",
    "sampled_secondary_records",
    "sampled_supplementary_records",
    "sampled_unmapped_records",
    "sampled_mean_mapq",
    "sampled_pct_duplicate",
    "sampled_pct_secondary",
    "sampled_pct_supplementary",
    "sampled_pct_clipped",
    "sampled_mean_read_length",
    "sampled_median_read_length",
    "sampled_mean_insert_size",
    "sampled_median_insert_size",
    "caller_input_class",
    "production_eligible",
]

FIELDNAMES_REGION_DEPTH = [
    "sample",
    "aligner",
    "deduper",
    "chrom",
    "start",
    "end",
    "region_name",
    "depth_class",
    "expected_gc",
    "total_records",
    "mapped_records",
    "primary_mapped_records",
    "duplicate_records",
    "secondary_records",
    "supplementary_records",
    "clipped_records",
    "overlap_bases",
    "read_bases",
    "mean_mapq",
    "present_for_depth",
    "fetch_status",
]

FIELDNAMES_FLAGS = [
    "sample",
    "aligner",
    "deduper",
    "scope",
    "total_records",
    "mapped_records",
    "primary_mapped_records",
    "duplicate_records",
    "secondary_records",
    "supplementary_records",
    "unmapped_records",
    "clipped_records",
    "mean_mapq",
    "pct_duplicate",
    "pct_secondary",
    "pct_supplementary",
    "pct_clipped",
    "mean_read_length",
    "median_read_length",
    "mean_insert_size",
    "median_insert_size",
]

FIELDNAMES_REQUIRED = [
    "sample",
    "aligner",
    "deduper",
    "requirement",
    "status",
    "observed",
    "threshold",
    "detail",
]

FIELDNAMES_MQC = [
    "sample",
    "aligner",
    "deduper",
    "production_eligible",
    "input_scope",
    "quickcheck_status",
    "exon16_status",
    "exon78_status",
    "norm_bin_status",
    "selected_snp_status",
    "target_variant_status",
    "mean_mapq_sample",
    "duplicate_pct_sample",
    "secondary_pct_sample",
    "supplementary_pct_sample",
    "clipped_pct_sample",
]


def _load_pysam():
    try:
        import pysam  # type: ignore
    except ImportError as exc:
        raise SystemExit("pysam is required for smn12_input_qc") from exc
    return pysam


def _pct(numerator: int | float, denominator: int | float) -> str:
    if not denominator:
        return "0.000000"
    return f"{100.0 * float(numerator) / float(denominator):.6f}"


def _mean(values: list[int]) -> str:
    if not values:
        return "0.000000"
    return f"{statistics.fmean(values):.6f}"


def _median(values: list[int]) -> str:
    if not values:
        return "0.000000"
    return f"{statistics.median(values):.6f}"


def _is_clipped(read: Any) -> bool:
    return any(op in {4, 5} and length > 0 for op, length in (read.cigartuples or []))


def _update_stats(stats: Counter[str], read: Any) -> None:
    stats["total_records"] += 1
    if read.is_unmapped:
        stats["unmapped_records"] += 1
    else:
        stats["mapped_records"] += 1
        if not read.is_secondary and not read.is_supplementary:
            stats["primary_mapped_records"] += 1
    if read.is_duplicate:
        stats["duplicate_records"] += 1
    if read.is_secondary:
        stats["secondary_records"] += 1
    if read.is_supplementary:
        stats["supplementary_records"] += 1
    if _is_clipped(read):
        stats["clipped_records"] += 1


def _flag_row(sample: str, aligner: str, deduper: str, scope: str, stats: Counter[str], mapqs: list[int], read_lengths: list[int], inserts: list[int]) -> dict[str, str]:
    total = stats["total_records"]
    return {
        "sample": sample,
        "aligner": aligner,
        "deduper": deduper,
        "scope": scope,
        "total_records": str(total),
        "mapped_records": str(stats["mapped_records"]),
        "primary_mapped_records": str(stats["primary_mapped_records"]),
        "duplicate_records": str(stats["duplicate_records"]),
        "secondary_records": str(stats["secondary_records"]),
        "supplementary_records": str(stats["supplementary_records"]),
        "unmapped_records": str(stats["unmapped_records"]),
        "clipped_records": str(stats["clipped_records"]),
        "mean_mapq": _mean(mapqs),
        "pct_duplicate": _pct(stats["duplicate_records"], total),
        "pct_secondary": _pct(stats["secondary_records"], total),
        "pct_supplementary": _pct(stats["supplementary_records"], total),
        "pct_clipped": _pct(stats["clipped_records"], total),
        "mean_read_length": _mean(read_lengths),
        "median_read_length": _median(read_lengths),
        "mean_insert_size": _mean(inserts),
        "median_insert_size": _median(inserts),
    }


def _read_regions(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 5:
                raise SystemExit(f"Malformed SMN region row in {path}: {line}")
            rows.append(
                {
                    "chrom": parts[0],
                    "start": parts[1],
                    "end": parts[2],
                    "region_name": parts[3],
                    "depth_class": parts[4],
                    "expected_gc": parts[5] if len(parts) > 5 else "NA",
                }
            )
    return rows


def _read_snp_sites(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 7:
                raise SystemExit(f"Malformed SMN SNP row in {path}: {line}")
            rows.append(
                {
                    "chr": parts[0],
                    "pos_smn1": parts[1],
                    "base_smn1": parts[2],
                    "pos_smn2": parts[3],
                    "base_smn2": parts[4],
                    "annotation": parts[5],
                    "selected": parts[6],
                }
            )
    return rows


def _read_target_sites(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 6:
                raise SystemExit(f"Malformed SMN target variant row in {path}: {line}")
            rows.append(
                {
                    "chr": parts[0],
                    "pos_smn1": parts[1],
                    "base_ref": parts[2],
                    "pos_smn2": parts[3],
                    "base_alt": parts[4],
                    "annotation": parts[5],
                }
            )
    return rows


def _sample_records(aln: Any, max_records: int) -> tuple[Counter[str], list[int], list[int], list[int]]:
    stats: Counter[str] = Counter()
    mapqs: list[int] = []
    read_lengths: list[int] = []
    inserts: list[int] = []
    for index, read in enumerate(aln.fetch(until_eof=True)):
        if index >= max_records:
            break
        _update_stats(stats, read)
        if not read.is_unmapped:
            mapqs.append(int(read.mapping_quality))
        if read.query_length:
            read_lengths.append(int(read.query_length))
        if read.template_length:
            inserts.append(abs(int(read.template_length)))
    return stats, mapqs, read_lengths, inserts


def _region_depth_rows(aln: Any, regions: list[dict[str, str]], sample: str, aligner: str, deduper: str) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    flag_rows: list[dict[str, str]] = []
    for region in regions:
        stats: Counter[str] = Counter()
        mapqs: list[int] = []
        read_lengths: list[int] = []
        inserts: list[int] = []
        overlap_bases = 0
        fetch_status = "ok"
        chrom = region["chrom"]
        start = int(region["start"])
        end = int(region["end"])
        try:
            iterator = aln.fetch(chrom, start, end)
            for read in iterator:
                _update_stats(stats, read)
                if not read.is_unmapped:
                    mapqs.append(int(read.mapping_quality))
                if read.query_length:
                    read_lengths.append(int(read.query_length))
                if read.template_length:
                    inserts.append(abs(int(read.template_length)))
                try:
                    overlap = read.get_overlap(start, end)
                except ValueError:
                    overlap = None
                if overlap is not None:
                    overlap_bases += int(overlap)
        except (ValueError, OSError) as exc:
            fetch_status = f"error:{type(exc).__name__}"
        rows.append(
            {
                "sample": sample,
                "aligner": aligner,
                "deduper": deduper,
                "chrom": chrom,
                "start": str(start),
                "end": str(end),
                "region_name": region["region_name"],
                "depth_class": region["depth_class"],
                "expected_gc": region["expected_gc"],
                "total_records": str(stats["total_records"]),
                "mapped_records": str(stats["mapped_records"]),
                "primary_mapped_records": str(stats["primary_mapped_records"]),
                "duplicate_records": str(stats["duplicate_records"]),
                "secondary_records": str(stats["secondary_records"]),
                "supplementary_records": str(stats["supplementary_records"]),
                "clipped_records": str(stats["clipped_records"]),
                "overlap_bases": str(overlap_bases),
                "read_bases": str(sum(read_lengths)),
                "mean_mapq": _mean(mapqs),
                "present_for_depth": "true" if stats["primary_mapped_records"] > 0 else "false",
                "fetch_status": fetch_status,
            }
        )
        flag_rows.append(
            _flag_row(
                sample,
                aligner,
                deduper,
                f"region:{region['region_name']}:{region['depth_class']}",
                stats,
                mapqs,
                read_lengths,
                inserts,
            )
        )
    return rows, flag_rows


def _pileup_site_counts(aln: Any, chrom: str, pos_1based: int) -> Counter[str]:
    counts: Counter[str] = Counter()
    try:
        pileup_iter = aln.pileup(chrom, pos_1based - 1, pos_1based, truncate=True, stepper="all")
        for column in pileup_iter:
            if column.reference_pos != pos_1based - 1:
                continue
            for read in column.pileups:
                alnseg = read.alignment
                if read.is_del or read.is_refskip or read.query_position is None or alnseg.is_unmapped:
                    counts["unusable"] += 1
                    continue
                if alnseg.is_secondary:
                    counts["secondary"] += 1
                if alnseg.is_supplementary:
                    counts["supplementary"] += 1
                if alnseg.is_duplicate:
                    counts["duplicate"] += 1
                if not alnseg.is_secondary and not alnseg.is_supplementary:
                    counts["primary"] += 1
                    base = alnseg.query_sequence[read.query_position].upper()
                    counts[f"base_{base}"] += 1
    except (ValueError, OSError):
        counts["fetch_error"] += 1
    return counts


def _site_status_rows(aln: Any, sample: str, aligner: str, deduper: str, snps: list[dict[str, str]], targets: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    required_rows: list[dict[str, str]] = []
    mqc_details: list[dict[str, str]] = []

    selected_sites = [row for row in snps if row["selected"].lower() == "yes"]
    selected_observed = 0
    selected_total = 0
    for row in selected_sites:
        for locus in ("smn1", "smn2"):
            pos = int(row[f"pos_{locus}"])
            counts = _pileup_site_counts(aln, row["chr"], pos)
            selected_total += 1
            if counts["primary"] > 0:
                selected_observed += 1
            mqc_details.append(
                {
                    "requirement": f"selected_snp_{locus}_{row['annotation']}_{pos}",
                    "observed": str(counts["primary"]),
                    "detail": json.dumps(dict(counts), sort_keys=True),
                }
            )
    required_rows.append(
        {
            "sample": sample,
            "aligner": aligner,
            "deduper": deduper,
            "requirement": "selected_snp_sites",
            "status": "PASS" if selected_total and selected_observed == selected_total else "FAIL",
            "observed": f"{selected_observed}/{selected_total}",
            "threshold": "all selected SMN1/SMN2 differentiating sites have primary read support",
            "detail": json.dumps(mqc_details, sort_keys=True),
        }
    )

    target_observed = 0
    target_total = 0
    target_details: list[dict[str, str]] = []
    for row in targets:
        for locus in ("smn1", "smn2"):
            pos = int(row[f"pos_{locus}"])
            counts = _pileup_site_counts(aln, row["chr"], pos)
            target_total += 1
            if counts["primary"] > 0:
                target_observed += 1
            target_details.append(
                {
                    "requirement": f"target_variant_{locus}_{row['annotation']}_{pos}",
                    "observed": str(counts["primary"]),
                    "detail": json.dumps(dict(counts), sort_keys=True),
                }
            )
    required_rows.append(
        {
            "sample": sample,
            "aligner": aligner,
            "deduper": deduper,
            "requirement": "target_variant_sites",
            "status": "PASS" if target_total and target_observed == target_total else "FAIL",
            "observed": f"{target_observed}/{target_total}",
            "threshold": "all SMN1/SMN2 target variant sites have primary read support",
            "detail": json.dumps(target_details, sort_keys=True),
        }
    )
    return required_rows, target_details


def _required_region_rows(sample: str, aligner: str, deduper: str, region_rows: list[dict[str, str]], min_norm_fraction: float, input_scope: str, quickcheck_status: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    by_class: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in region_rows:
        by_class[row["depth_class"]].append(row)

    for depth_class in ("exon16", "exon78"):
        class_rows = by_class.get(depth_class, [])
        present = sum(1 for row in class_rows if row["present_for_depth"] == "true")
        total = len(class_rows)
        primary = sum(int(row["primary_mapped_records"]) for row in class_rows)
        rows.append(
            {
                "sample": sample,
                "aligner": aligner,
                "deduper": deduper,
                "requirement": depth_class,
                "status": "PASS" if total and present == total and primary > 0 else "FAIL",
                "observed": f"{present}/{total};primary_mapped_records={primary}",
                "threshold": "all SMN1 and SMN2 regions in class have primary mapped read support",
                "detail": json.dumps([row["region_name"] for row in class_rows if row["present_for_depth"] != "true"]),
            }
        )

    norm_rows = by_class.get("norm", [])
    norm_present = sum(1 for row in norm_rows if row["present_for_depth"] == "true")
    norm_total = len(norm_rows)
    norm_fraction = float(norm_present) / float(norm_total or 1)
    rows.append(
        {
            "sample": sample,
            "aligner": aligner,
            "deduper": deduper,
            "requirement": "normalization_bins",
            "status": "PASS" if norm_total and norm_fraction >= min_norm_fraction else "FAIL",
            "observed": f"{norm_present}/{norm_total};fraction={norm_fraction:.6f}",
            "threshold": f">={min_norm_fraction:.6f}",
            "detail": "normalization-bin completeness",
        }
    )

    rows.append(
        {
            "sample": sample,
            "aligner": aligner,
            "deduper": deduper,
            "requirement": "whole_genome_input",
            "status": "PASS" if input_scope == "whole_genome" else "FAIL",
            "observed": input_scope,
            "threshold": "whole_genome",
            "detail": "SMNCopyNumberCaller production runs must use whole-genome BAM/CRAM, not a diagnostic bamlet/cramlet.",
        }
    )
    rows.append(
        {
            "sample": sample,
            "aligner": aligner,
            "deduper": deduper,
            "requirement": "quickcheck",
            "status": "PASS" if quickcheck_status == "PASS" else "FAIL",
            "observed": quickcheck_status,
            "threshold": "PASS",
            "detail": "pysam.quickcheck input integrity status",
        }
    )
    return rows


def _input_scope(sq_count: int, total_sq_bases: int) -> str:
    if sq_count >= 24 and total_sq_bases >= 1_000_000_000:
        return "whole_genome"
    return "diagnostic_bamlet_or_cramlet"


def _write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def run(args: argparse.Namespace) -> int:
    pysam = _load_pysam()
    input_path = Path(args.input)
    reference_path = Path(args.reference)
    quickcheck_status = "PASS"
    try:
        pysam.quickcheck(str(input_path))
    except Exception as exc:
        quickcheck_status = f"FAIL:{type(exc).__name__}"

    try:
        aln = pysam.AlignmentFile(str(input_path), reference_filename=str(reference_path))
        sq_rows = list(aln.header.get("SQ", []))
        rg_rows = list(aln.header.get("RG", []))
        sq_count = len(sq_rows)
        total_sq_bases = sum(int(row.get("LN", 0)) for row in sq_rows)
        scope = _input_scope(sq_count, total_sq_bases)
        sample_names = sorted({str(row.get("SM", "")) for row in rg_rows if row.get("SM")})

        sample_stats, sample_mapqs, sample_lengths, sample_inserts = _sample_records(
            aln, args.max_sample_records
        )
        aln.close()

        regions = _read_regions(Path(args.regions_bed))
        aln = pysam.AlignmentFile(str(input_path), reference_filename=str(reference_path))
        region_rows, region_flag_rows = _region_depth_rows(
            aln, regions, args.sample, args.aligner, args.deduper
        )
        aln.close()

        required_rows = _required_region_rows(
            args.sample,
            args.aligner,
            args.deduper,
            region_rows,
            args.min_norm_bin_present_fraction,
            scope,
            quickcheck_status,
        )
        aln = pysam.AlignmentFile(str(input_path), reference_filename=str(reference_path))
        site_rows, _ = _site_status_rows(
            aln,
            args.sample,
            args.aligner,
            args.deduper,
            _read_snp_sites(Path(args.snp_file)),
            _read_target_sites(Path(args.target_variant_file)),
        )
        aln.close()
        required_rows.extend(site_rows)

        production_eligible = "true" if all(row["status"] == "PASS" for row in required_rows) else "false"
        input_qc_row = {
            "sample": args.sample,
            "aligner": args.aligner,
            "deduper": args.deduper,
            "input_path": str(input_path),
            "reference_path": str(reference_path),
            "input_format": input_path.suffix.lstrip(".").lower() or "unknown",
            "quickcheck_status": quickcheck_status,
            "sq_count": str(sq_count),
            "total_sq_bases": str(total_sq_bases),
            "input_scope": scope,
            "read_group_count": str(len(rg_rows)),
            "read_groups_json": json.dumps(rg_rows, sort_keys=True),
            "sample_names_json": json.dumps(sample_names),
            "sampled_records": str(sample_stats["total_records"]),
            "sampled_mapped_records": str(sample_stats["mapped_records"]),
            "sampled_primary_records": str(sample_stats["primary_mapped_records"]),
            "sampled_duplicate_records": str(sample_stats["duplicate_records"]),
            "sampled_secondary_records": str(sample_stats["secondary_records"]),
            "sampled_supplementary_records": str(sample_stats["supplementary_records"]),
            "sampled_unmapped_records": str(sample_stats["unmapped_records"]),
            "sampled_mean_mapq": _mean(sample_mapqs),
            "sampled_pct_duplicate": _pct(sample_stats["duplicate_records"], sample_stats["total_records"]),
            "sampled_pct_secondary": _pct(sample_stats["secondary_records"], sample_stats["total_records"]),
            "sampled_pct_supplementary": _pct(sample_stats["supplementary_records"], sample_stats["total_records"]),
            "sampled_pct_clipped": _pct(sample_stats["clipped_records"], sample_stats["total_records"]),
            "sampled_mean_read_length": _mean(sample_lengths),
            "sampled_median_read_length": _median(sample_lengths),
            "sampled_mean_insert_size": _mean(sample_inserts),
            "sampled_median_insert_size": _median(sample_inserts),
            "caller_input_class": "whole_genome_wgs_bam_cram",
            "production_eligible": production_eligible,
        }
        flag_rows = [
            _flag_row(
                args.sample,
                args.aligner,
                args.deduper,
                "sampled_whole_input",
                sample_stats,
                sample_mapqs,
                sample_lengths,
                sample_inserts,
            )
        ]
        flag_rows.extend(region_flag_rows)

        status_by_requirement = {row["requirement"]: row["status"] for row in required_rows}
        mqc_row = {
            "sample": args.sample,
            "aligner": args.aligner,
            "deduper": args.deduper,
            "production_eligible": production_eligible,
            "input_scope": scope,
            "quickcheck_status": quickcheck_status,
            "exon16_status": status_by_requirement.get("exon16", "FAIL"),
            "exon78_status": status_by_requirement.get("exon78", "FAIL"),
            "norm_bin_status": status_by_requirement.get("normalization_bins", "FAIL"),
            "selected_snp_status": status_by_requirement.get("selected_snp_sites", "FAIL"),
            "target_variant_status": status_by_requirement.get("target_variant_sites", "FAIL"),
            "mean_mapq_sample": _mean(sample_mapqs),
            "duplicate_pct_sample": _pct(sample_stats["duplicate_records"], sample_stats["total_records"]),
            "secondary_pct_sample": _pct(sample_stats["secondary_records"], sample_stats["total_records"]),
            "supplementary_pct_sample": _pct(sample_stats["supplementary_records"], sample_stats["total_records"]),
            "clipped_pct_sample": _pct(sample_stats["clipped_records"], sample_stats["total_records"]),
        }

        _write_tsv(Path(args.input_qc), FIELDNAMES_INPUT_QC, [input_qc_row])
        _write_tsv(Path(args.region_depth), FIELDNAMES_REGION_DEPTH, region_rows)
        _write_tsv(Path(args.required_status), FIELDNAMES_REQUIRED, required_rows)
        _write_tsv(Path(args.alignment_flags), FIELDNAMES_FLAGS, flag_rows)
        _write_tsv(Path(args.mqc), FIELDNAMES_MQC, [mqc_row])

        if production_eligible != "true" and not args.allow_failed_required_checks:
            failed = ", ".join(row["requirement"] for row in required_rows if row["status"] != "PASS")
            raise SystemExit(f"SMN12 input preflight failed required checks: {failed}")
    finally:
        aln.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--regions-bed", required=True)
    parser.add_argument("--snp-file", required=True)
    parser.add_argument("--target-variant-file", required=True)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--aligner", required=True)
    parser.add_argument("--deduper", required=True)
    parser.add_argument("--input-qc", required=True)
    parser.add_argument("--region-depth", required=True)
    parser.add_argument("--required-status", required=True)
    parser.add_argument("--alignment-flags", required=True)
    parser.add_argument("--mqc", required=True)
    parser.add_argument("--max-sample-records", type=int, default=200000)
    parser.add_argument("--min-norm-bin-present-fraction", type=float, default=0.95)
    parser.add_argument(
        "--allow-failed-required-checks",
        action="store_true",
        help=(
            "Write QC outputs and return success even when required SMN12 depth/site "
            "checks fail. This is for exploratory caller runs only; production_eligible "
            "remains false in the emitted QC tables."
        ),
    )
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
