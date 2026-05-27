#!/usr/bin/env python3
"""Run Hail CHARR and write a small deterministic TSV."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--input-vcf", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--ref-af-resource", required=True)
    parser.add_argument("--ref-af-field", required=True)
    parser.add_argument("--hail-reference-genome", required=True)
    parser.add_argument("--autosome-contigs", required=True)
    parser.add_argument("--min-af", required=True, type=float)
    parser.add_argument("--max-af", required=True, type=float)
    parser.add_argument("--min-dp", required=True, type=int)
    parser.add_argument("--max-dp", required=True, type=int)
    parser.add_argument("--min-gq", required=True, type=int)
    parser.add_argument("--tmp-dir", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    import hail as hl

    contigs = [item.strip() for item in args.autosome_contigs.split(",") if item.strip()]
    if not contigs:
        raise ValueError("--autosome-contigs must contain at least one contig")

    hl.init(tmp_dir=args.tmp_dir, quiet=True)
    mt = hl.import_vcf(
        args.input_vcf,
        force_bgz=True,
        reference_genome=args.hail_reference_genome,
    )
    mt = mt.filter_rows(hl.literal(set(contigs)).contains(mt.locus.contig))
    mt = hl.split_multi_hts(mt)
    ref_ht = hl.read_table(args.ref_af_resource)
    ref_row = ref_ht[mt.row_key]
    if args.ref_af_field not in ref_ht.row:
        raise ValueError(
            f"CHARR ref AF resource lacks configured field {args.ref_af_field!r}"
        )
    result = hl.compute_charr(
        mt,
        min_af=args.min_af,
        max_af=args.max_af,
        min_dp=args.min_dp,
        max_dp=args.max_dp,
        min_gq=args.min_gq,
        ref_AF=ref_row[args.ref_af_field],
    )
    rows = result.to_pandas()
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["sample", "charr"],
            delimiter="\t",
        )
        writer.writeheader()
        if rows.empty:
            writer.writerow({"sample": args.sample, "charr": ""})
        else:
            for row in rows.to_dict(orient="records"):
                writer.writerow(
                    {
                        "sample": row.get("s", row.get("sample", args.sample)),
                        "charr": row.get("charr", ""),
                    }
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
