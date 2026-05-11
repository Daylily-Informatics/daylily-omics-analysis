from __future__ import annotations

import argparse
from pathlib import Path

from .engine import (
    AltairValidationInputs,
    build_boundary_rows_from_vcfs,
    build_coverage_row_from_mosdepth,
    build_validation_artifacts,
    merge_coverage_tsvs,
    sha256,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build Altair validation artifacts.")
    subparsers = parser.add_subparsers(dest="command")

    build = subparsers.add_parser(
        "build",
        help="Build the complete validation_artifacts directory.",
    )
    build.add_argument("--rr-manifest", required=True, type=Path)
    build.add_argument("--bar-manifest", required=True, type=Path)
    build.add_argument(
        "--giab-concordance",
        required=True,
        action="append",
        type=Path,
        help="GIAB concordance TSV. May be provided more than once.",
    )
    build.add_argument("--rr-coverage-callability", type=Path)
    build.add_argument("--boundary-verification", type=Path)
    build.add_argument("--report-template-docx", type=Path)
    build.add_argument("--report-docx", type=Path)
    build.add_argument("--output-dir", required=True, type=Path)

    coverage = subparsers.add_parser(
        "coverage-from-mosdepth",
        help="Convert one RR mosdepth result into one coverage/callability TSV row.",
    )
    coverage.add_argument("--sample-id", required=True)
    coverage.add_argument("--run-id", default="")
    coverage.add_argument("--library-id", default="")
    coverage.add_argument("--rr-bed", required=True, type=Path)
    coverage.add_argument("--rr-bed-name", required=True)
    coverage.add_argument("--rr-bed-sha256", default="")
    coverage.add_argument("--rr-total-bases", required=True, type=int)
    coverage.add_argument("--regions-bed-gz", required=True, type=Path)
    coverage.add_argument("--thresholds-bed-gz", required=True, type=Path)
    coverage.add_argument("--coverage-tool-version", required=True)
    coverage.add_argument(
        "--callable-definition",
        default="mosdepth DP>=20x over full Altair_RR_v1",
    )
    coverage.add_argument("--output", required=True, type=Path)

    merge = subparsers.add_parser(
        "merge-coverage",
        help="Merge per-sample RR coverage/callability TSVs.",
    )
    merge.add_argument("--output", required=True, type=Path)
    merge.add_argument("inputs", nargs="+", type=Path)

    boundary = subparsers.add_parser(
        "boundary-from-vcf",
        help="Verify released VCF calls are within the Altair RR and <=50 bp indels.",
    )
    boundary.add_argument("--rr-bed", required=True, type=Path)
    boundary.add_argument("--rr-bed-name", required=True)
    boundary.add_argument("--rr-bed-sha256", default="")
    boundary.add_argument("--output", required=True, type=Path)
    boundary.add_argument("vcfs", nargs="+", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "build":
        result = build_validation_artifacts(
            AltairValidationInputs(
                rr_manifest=args.rr_manifest,
                bar_manifest=args.bar_manifest,
                giab_concordance=tuple(args.giab_concordance),
                output_dir=args.output_dir,
                rr_coverage_callability=args.rr_coverage_callability,
                boundary_verification=args.boundary_verification,
                report_template_docx=args.report_template_docx,
                report_docx=args.report_docx,
            )
        )
        print(result["validation_summary"]["overall_status"])
        return 0
    if args.command == "coverage-from-mosdepth":
        rr_sha = args.rr_bed_sha256 or sha256(args.rr_bed)
        row = build_coverage_row_from_mosdepth(
            sample_id=args.sample_id,
            run_id=args.run_id,
            library_id=args.library_id,
            rr_bed_name=args.rr_bed_name,
            rr_bed_sha256=rr_sha,
            rr_total_bases=args.rr_total_bases,
            regions_bed_gz=args.regions_bed_gz,
            thresholds_bed_gz=args.thresholds_bed_gz,
            coverage_tool_version=args.coverage_tool_version,
            callable_definition=args.callable_definition,
        )
        merge_coverage_tsvs([], args.output)
        with args.output.open("a", encoding="utf-8") as handle:
            handle.write(
                "\t".join(
                    row[field]
                    for field in (
                        "sample_id",
                        "run_id",
                        "library_id",
                        "rr_bed_name",
                        "rr_bed_sha256",
                        "rr_total_bases",
                        "median_rr_depth",
                        "mean_rr_depth",
                        "pct_rr_bases_ge_10x",
                        "pct_rr_bases_ge_20x",
                        "callable_fraction",
                        "callable_definition",
                        "coverage_tool",
                        "coverage_tool_version",
                        "status",
                        "reason",
                    )
                )
                + "\n"
            )
        return 0
    if args.command == "merge-coverage":
        merge_coverage_tsvs(args.inputs, args.output)
        return 0
    if args.command == "boundary-from-vcf":
        rr_sha = args.rr_bed_sha256 or sha256(args.rr_bed)
        build_boundary_rows_from_vcfs(
            vcf_paths=args.vcfs,
            rr_bed=args.rr_bed,
            rr_bed_name=args.rr_bed_name,
            rr_bed_sha256=rr_sha,
            output=args.output,
        )
        return 0
    parser.error("a subcommand is required")
    return 2
