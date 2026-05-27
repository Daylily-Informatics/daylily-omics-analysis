#!/usr/bin/env python3
"""Compile contamination and identity evidence into MultiQC-ready TSVs."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


IDENTITY_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "snv_caller",
    "tool",
    "evidence_type",
    "method",
    "metric_name",
    "metric_value",
    "contamination_fraction",
    "contamination_pct",
    "status",
    "tool_pass_fail",
    "tool_reason",
    "source_path",
]

NGSTROUBLEFINDER_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "tool_sample",
    "source_path",
    "raw_payload",
]

HAPLOCHECK_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "snv_caller",
    "input_mode",
    "contamination_status",
    "contamination_level",
    "distance",
    "sample_coverage",
    "major_haplogroup",
    "minor_haplogroup",
    "source_path",
    "raw_payload",
]

READ_HAPS_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "snv_caller",
    "snp_pairs",
    "error_pairs",
    "double_error_pair_count",
    "double_error_fraction",
    "rel_error_fraction",
    "nonsense_fraction",
    "pass_fail",
    "reason",
    "source_path",
]

CHARR_FIELDS = [
    "Sample",
    "base_sample",
    "sample_id",
    "external_sample_id",
    "aligner",
    "deduper",
    "snv_caller",
    "charr",
    "source_path",
]


def _write_header(path: str, fields: list[str]) -> tuple[csv.DictWriter, object]:
    out_path = Path(path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    handle = out_path.open("w", newline="", encoding="utf-8")
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
    writer.writeheader()
    return writer, handle


def _safe_pct(value: str | None) -> str:
    try:
        return str(float(str(value).strip()) * 100.0)
    except (TypeError, ValueError):
        return ""


def _stage_sample_id(sample: str, aligner: str, deduper: str, caller: str = "") -> str:
    return ".".join(part for part in [sample, aligner, deduper, caller] if part)


def _path_parts(path: str) -> tuple[str, ...]:
    return Path(path).parts


def _alignment_context(path: str) -> tuple[str, str, str]:
    parts = _path_parts(path)
    for index, part in enumerate(parts):
        if part == "align" and index >= 1 and index + 2 < len(parts):
            return parts[index - 1], parts[index + 1], parts[index + 2]
    raise ValueError(f"Could not parse alignment context from {path}")


def _caller_context(path: str) -> str:
    parts = _path_parts(path)
    try:
        snv_index = parts.index("snv")
    except ValueError:
        return ""
    if snv_index + 1 >= len(parts):
        return ""
    return parts[snv_index + 1]


def _batch_context(path: str) -> tuple[str, str]:
    parts = _path_parts(path)
    try:
        idx = parts.index("contam_identity")
    except ValueError as exc:
        raise ValueError(f"Could not parse contam_identity batch context from {path}") from exc
    if idx + 2 >= len(parts):
        raise ValueError(f"Incomplete contam_identity batch path: {path}")
    return parts[idx + 1], parts[idx + 2]


def _sample_context(
    path: str, sample_map: dict[str, str], *, caller_required: bool = False
) -> tuple[str, str, str, str, str, str]:
    sample, aligner, deduper = _alignment_context(path)
    caller = _caller_context(path)
    if caller_required and not caller:
        raise ValueError(f"Could not parse SNV caller context from {path}")
    stage_sample = _stage_sample_id(sample, aligner, deduper, caller)
    return stage_sample, sample, sample_map.get(sample, sample), aligner, deduper, caller


def _read_tsv_rows(path: str) -> list[dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def _first_existing_value(row: dict[str, str], names: tuple[str, ...]) -> str:
    lower = {key.strip().lower().replace(" ", "_"): value for key, value in row.items()}
    for name in names:
        key = name.strip().lower().replace(" ", "_")
        if key in lower:
            return str(lower[key])
    return ""


def _raw_payload(row: dict[str, str]) -> str:
    return json.dumps(row, sort_keys=True, separators=(",", ":"))


def _identity_row(
    *,
    sample: str,
    base_sample: str,
    external: str,
    aligner: str,
    deduper: str,
    caller: str = "",
    tool: str,
    evidence_type: str,
    method: str,
    metric_name: str,
    metric_value: str,
    contamination_fraction: str = "",
    contamination_pct: str = "",
    status: str = "",
    pass_fail: str = "",
    reason: str = "",
    source_path: str,
) -> dict[str, str]:
    return {
        "Sample": sample,
        "base_sample": base_sample,
        "sample_id": base_sample,
        "external_sample_id": external,
        "aligner": aligner,
        "deduper": deduper,
        "snv_caller": caller,
        "tool": tool,
        "evidence_type": evidence_type,
        "method": method,
        "metric_name": metric_name,
        "metric_value": metric_value,
        "contamination_fraction": contamination_fraction,
        "contamination_pct": contamination_pct,
        "status": status,
        "tool_pass_fail": pass_fail,
        "tool_reason": reason,
        "source_path": source_path,
    }


def _emit_existing_contamination(identity_writer: csv.DictWriter, paths: list[str]) -> None:
    for path in paths:
        for row in _read_tsv_rows(path):
            identity_writer.writerow(
                _identity_row(
                    sample=row.get("Sample", ""),
                    base_sample=row.get("base_sample", row.get("sample_id", "")),
                    external=row.get("external_sample_id", ""),
                    aligner=row.get("aligner", ""),
                    deduper=row.get("deduper", ""),
                    tool=row.get("tool", ""),
                    evidence_type="contamination",
                    method=row.get("method", ""),
                    metric_name="contamination_fraction",
                    metric_value=row.get("contamination_fraction", ""),
                    contamination_fraction=row.get("contamination_fraction", ""),
                    contamination_pct=row.get("contamination_pct", ""),
                    status=row.get("status", ""),
                    source_path=row.get("source_path", path),
                )
            )


def _emit_ngstroublefinder(
    identity_writer: csv.DictWriter,
    ngs_writer: csv.DictWriter,
    sample_map: dict[str, str],
    paths: list[str],
) -> None:
    for path in paths:
        aligner, deduper = _batch_context(path)
        for row in _read_tsv_rows(path):
            tool_sample = _first_existing_value(row, ("Sample_Name", "Sample", "sample"))
            base_sample = tool_sample.split(".", 1)[0]
            sample = _stage_sample_id(base_sample, aligner, deduper)
            external = sample_map.get(base_sample, base_sample)
            ngs_writer.writerow(
                {
                    "Sample": sample,
                    "base_sample": base_sample,
                    "sample_id": base_sample,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "tool_sample": tool_sample,
                    "source_path": path,
                    "raw_payload": _raw_payload(row),
                }
            )
            for metric in ("contamination", "contamination_score", "sex", "kinship", "swap"):
                value = _first_existing_value(row, (metric,))
                if value:
                    identity_writer.writerow(
                        _identity_row(
                            sample=sample,
                            base_sample=base_sample,
                            external=external,
                            aligner=aligner,
                            deduper=deduper,
                            tool="ngstroublefinder",
                            evidence_type="contam_identity",
                            method="ngstroublefinder",
                            metric_name=metric,
                            metric_value=value,
                            source_path=path,
                        )
                    )


def _emit_haplocheck(
    identity_writer: csv.DictWriter,
    haplo_writer: csv.DictWriter,
    sample_map: dict[str, str],
    paths: list[str],
) -> None:
    for path in paths:
        sample, base_sample, external, aligner, deduper, caller = _sample_context(
            path, sample_map
        )
        input_mode = "vcf" if caller else "bam"
        for row in _read_tsv_rows(path):
            status = _first_existing_value(
                row, ("Contamination Status", "contamination_status", "status")
            )
            level = _first_existing_value(
                row, ("Contamination Level", "contamination_level", "level")
            )
            out_row = {
                "Sample": sample,
                "base_sample": base_sample,
                "sample_id": base_sample,
                "external_sample_id": external,
                "aligner": aligner,
                "deduper": deduper,
                "snv_caller": caller,
                "input_mode": input_mode,
                "contamination_status": status,
                "contamination_level": level,
                "distance": _first_existing_value(row, ("Distance", "distance")),
                "sample_coverage": _first_existing_value(
                    row, ("Sample Coverage", "sample_coverage", "coverage")
                ),
                "major_haplogroup": _first_existing_value(
                    row, ("Major Haplogroup", "major_haplogroup")
                ),
                "minor_haplogroup": _first_existing_value(
                    row, ("Minor Haplogroup", "minor_haplogroup")
                ),
                "source_path": path,
                "raw_payload": _raw_payload(row),
            }
            haplo_writer.writerow(out_row)
            identity_writer.writerow(
                _identity_row(
                    sample=sample,
                    base_sample=base_sample,
                    external=external,
                    aligner=aligner,
                    deduper=deduper,
                    caller=caller,
                    tool="haplocheck",
                    evidence_type="mtdna_contamination_proxy",
                    method=input_mode,
                    metric_name="contamination_level",
                    metric_value=level,
                    contamination_fraction=level,
                    contamination_pct=_safe_pct(level),
                    status=status,
                    source_path=path,
                )
            )


def _read_read_haps_row(path: str) -> dict[str, str]:
    lines = [
        line.strip()
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if len(lines) < 2:
        return {}
    header = lines[0].split()
    values = lines[1].split()
    return dict(zip(header, values))


def _emit_read_haps(
    identity_writer: csv.DictWriter,
    read_haps_writer: csv.DictWriter,
    sample_map: dict[str, str],
    paths: list[str],
) -> None:
    for path in paths:
        sample, base_sample, external, aligner, deduper, caller = _sample_context(
            path, sample_map, caller_required=True
        )
        row = _read_read_haps_row(path)
        pass_fail = row.get("PASS_FAIL", "")
        reason = row.get("REASON", "")
        read_haps_writer.writerow(
            {
                "Sample": sample,
                "base_sample": base_sample,
                "sample_id": base_sample,
                "external_sample_id": external,
                "aligner": aligner,
                "deduper": deduper,
                "snv_caller": caller,
                "snp_pairs": row.get("SNP_PAIRS", ""),
                "error_pairs": row.get("ERROR_PAIRS", ""),
                "double_error_pair_count": row.get("DOUBLE_ERROR_PAIR_COUNT", ""),
                "double_error_fraction": row.get("DOUBLE_ERROR_FRACTION", ""),
                "rel_error_fraction": row.get("REL_ERROR_FRACTION", ""),
                "nonsense_fraction": row.get("NONSENSE_FRACTION", ""),
                "pass_fail": pass_fail,
                "reason": reason,
                "source_path": path,
            }
        )
        identity_writer.writerow(
            _identity_row(
                sample=sample,
                base_sample=base_sample,
                external=external,
                aligner=aligner,
                deduper=deduper,
                caller=caller,
                tool="read_haps",
                evidence_type="haplotype_contamination",
                method="three_haplotype_read_pairs",
                metric_name="double_error_fraction",
                metric_value=row.get("DOUBLE_ERROR_FRACTION", ""),
                status="tool_reported",
                pass_fail=pass_fail,
                reason=reason,
                source_path=path,
            )
        )


def _emit_charr(
    identity_writer: csv.DictWriter,
    charr_writer: csv.DictWriter,
    sample_map: dict[str, str],
    paths: list[str],
) -> None:
    for path in paths:
        sample, base_sample, external, aligner, deduper, caller = _sample_context(
            path, sample_map, caller_required=True
        )
        for row in _read_tsv_rows(path):
            charr = _first_existing_value(row, ("charr", "CHARR"))
            charr_writer.writerow(
                {
                    "Sample": sample,
                    "base_sample": base_sample,
                    "sample_id": base_sample,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "snv_caller": caller,
                    "charr": charr,
                    "source_path": path,
                }
            )
            identity_writer.writerow(
                _identity_row(
                    sample=sample,
                    base_sample=base_sample,
                    external=external,
                    aligner=aligner,
                    deduper=deduper,
                    caller=caller,
                    tool="charr",
                    evidence_type="contamination",
                    method="hail_compute_charr",
                    metric_name="charr",
                    metric_value=charr,
                    contamination_fraction=charr,
                    contamination_pct=_safe_pct(charr),
                    status="ok" if charr else "no_call",
                    source_path=path,
                )
            )


def compile_reports(args: argparse.Namespace) -> None:
    sample_map = json.loads(args.sample_map_json)
    identity_writer, identity_handle = _write_header(
        args.contam_identity_output, IDENTITY_FIELDS
    )
    ngs_writer, ngs_handle = _write_header(
        args.ngstroublefinder_output, NGSTROUBLEFINDER_FIELDS
    )
    haplo_writer, haplo_handle = _write_header(
        args.haplocheck_output, HAPLOCHECK_FIELDS
    )
    read_haps_writer, read_haps_handle = _write_header(
        args.read_haps_output, READ_HAPS_FIELDS
    )
    charr_writer, charr_handle = _write_header(args.charr_output, CHARR_FIELDS)

    try:
        _emit_existing_contamination(identity_writer, args.contamination)
        _emit_ngstroublefinder(identity_writer, ngs_writer, sample_map, args.ngstroublefinder)
        _emit_haplocheck(identity_writer, haplo_writer, sample_map, args.haplocheck)
        _emit_read_haps(identity_writer, read_haps_writer, sample_map, args.read_haps)
        _emit_charr(identity_writer, charr_writer, sample_map, args.charr)
    finally:
        for handle in (
            identity_handle,
            ngs_handle,
            haplo_handle,
            read_haps_handle,
            charr_handle,
        ):
            handle.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-map-json", required=True)
    parser.add_argument("--contam-identity-output", required=True)
    parser.add_argument("--ngstroublefinder-output", required=True)
    parser.add_argument("--haplocheck-output", required=True)
    parser.add_argument("--read-haps-output", required=True)
    parser.add_argument("--charr-output", required=True)
    parser.add_argument("--contamination", nargs="*", default=[])
    parser.add_argument("--ngstroublefinder", nargs="*", default=[])
    parser.add_argument("--haplocheck", nargs="*", default=[])
    parser.add_argument("--read-haps", nargs="*", default=[])
    parser.add_argument("--charr", nargs="*", default=[])
    args = parser.parse_args()
    compile_reports(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
