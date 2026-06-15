#!/usr/bin/env python3
"""Create deterministic, stage-scoped MultiQC input trees for DayOA reports."""

from __future__ import annotations

import argparse
import csv
import glob
import re
import shutil
from dataclasses import dataclass
from pathlib import Path


MANIFEST_FIELDS = [
    "Sample",
    "module",
    "stage",
    "base_sample",
    "aligner",
    "deduper",
    "caller",
    "input_kind",
    "source_path",
    "staged_path",
    "group_id",
]

METAGENOMICS_READ_SETS = {
    "s",
    "p",
}


@dataclass(frozen=True)
class StageParts:
    sample: str
    aligner: str = ""
    deduper: str = ""
    caller: str = ""
    stage: str = "sample"

    @property
    def stage_sample(self) -> str:
        parts = [self.sample, self.aligner, self.deduper, self.caller]
        return ".".join(part for part in parts if part)


class StagingError(RuntimeError):
    pass


class Stager:
    def __init__(self, input_root: Path, output_dir: Path, manifest: Path):
        self.input_root = input_root.resolve()
        self.output_dir = output_dir.resolve()
        self.manifest = manifest.resolve()
        self.rows: list[dict[str, str]] = []
        self.collision_groups: dict[tuple[str, str], str] = {}

    def reset(self) -> None:
        if self.output_dir.exists():
            shutil.rmtree(self.output_dir)
        self.output_dir.mkdir(parents=True)
        self.manifest.parent.mkdir(parents=True, exist_ok=True)

    def finish(self) -> None:
        with self.manifest.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=MANIFEST_FIELDS, delimiter="\t")
            writer.writeheader()
            for row in sorted(
                self.rows,
                key=lambda item: (
                    item["module"],
                    item["Sample"],
                    item["input_kind"],
                    item["staged_path"],
                ),
            ):
                writer.writerow(row)

    def copy_file(
        self,
        source: Path,
        rel_dest: Path,
        parts: StageParts,
        *,
        module: str,
        input_kind: str,
        group_id: str | None = None,
    ) -> Path:
        source = source.resolve()
        if not source.is_file():
            raise StagingError(f"missing MultiQC source file: {source}")
        dest = self.output_dir / rel_dest
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        self.add_manifest_row(
            source,
            dest,
            parts,
            module=module,
            input_kind=input_kind,
            group_id=group_id,
        )
        return dest

    def copy_tree_files(
        self,
        source_dir: Path,
        rel_dest_dir: Path,
        parts: StageParts,
        *,
        module: str,
        input_kind: str,
        group_id: str | None = None,
        patterns: tuple[str, ...] = ("*.txt", "*.tsv", "*.csv", "*.html", "*.json"),
    ) -> None:
        source_dir = source_dir.resolve()
        if not source_dir.is_dir():
            raise StagingError(f"missing MultiQC source directory: {source_dir}")
        copied = 0
        for pattern in patterns:
            for source in sorted(source_dir.rglob(pattern)):
                if not source.is_file():
                    continue
                rel = source.relative_to(source_dir)
                self.copy_file(
                    source,
                    rel_dest_dir / rel,
                    parts,
                    module=module,
                    input_kind=input_kind,
                    group_id=group_id or str(source_dir),
                )
                copied += 1
        if copied == 0:
            raise StagingError(f"no MultiQC files matched in {source_dir}")

    def add_manifest_row(
        self,
        source: Path,
        dest: Path,
        parts: StageParts,
        *,
        module: str,
        input_kind: str,
        group_id: str | None = None,
    ) -> None:
        sample = parts.stage_sample
        group = group_id or str(source)
        collision_key = (module, sample)
        prior_group = self.collision_groups.get(collision_key)
        if prior_group is not None and prior_group != group:
            raise StagingError(
                "MultiQC sample collision: "
                f"module={module} sample={sample} sources={prior_group} and {group}"
            )
        self.collision_groups[collision_key] = group
        self.rows.append(
            {
                "Sample": sample,
                "module": module,
                "stage": parts.stage,
                "base_sample": parts.sample,
                "aligner": parts.aligner,
                "deduper": parts.deduper,
                "caller": parts.caller,
                "input_kind": input_kind,
                "source_path": str(source),
                "staged_path": str(dest),
                "group_id": group,
            }
        )

    def add_manifest_sample_row(
        self,
        source: Path,
        dest: Path,
        *,
        sample: str,
        module: str,
        stage: str,
        base_sample: str = "",
        aligner: str = "",
        deduper: str = "",
        caller: str = "",
        input_kind: str,
        group_id: str,
    ) -> None:
        collision_key = (module, sample)
        prior_group = self.collision_groups.get(collision_key)
        if prior_group is not None and prior_group != group_id:
            raise StagingError(
                "MultiQC sample collision: "
                f"module={module} sample={sample} sources={prior_group} and {group_id}"
            )
        self.collision_groups[collision_key] = group_id
        self.rows.append(
            {
                "Sample": sample,
                "module": module,
                "stage": stage,
                "base_sample": base_sample,
                "aligner": aligner,
                "deduper": deduper,
                "caller": caller,
                "input_kind": input_kind,
                "source_path": str(source),
                "staged_path": str(dest),
                "group_id": group_id,
            }
        )


def path_parts(path: Path) -> tuple[str, ...]:
    return path.resolve().parts


def parse_alignment_parts(path: Path) -> StageParts:
    parts = path_parts(path)
    try:
        idx = parts.index("align")
    except ValueError as exc:
        raise StagingError(f"could not parse alignment stage from {path}") from exc
    if idx < 1 or idx + 2 >= len(parts):
        raise StagingError(f"incomplete alignment stage path: {path}")
    return StageParts(
        sample=parts[idx - 1],
        aligner=parts[idx + 1],
        deduper=parts[idx + 2],
        stage="alignment",
    )


def detect_metagenomics_read_set(path: Path) -> str:
    name = path.name
    for read_set in sorted(METAGENOMICS_READ_SETS):
        if f".{read_set}." in name:
            return read_set
    raise StagingError(f"could not determine metagenomics read set from {path}")


def with_metagenomics_read_set(parts: StageParts, read_set: str) -> StageParts:
    if read_set not in METAGENOMICS_READ_SETS:
        raise StagingError(f"unsupported metagenomics read set: {read_set}")
    return StageParts(
        sample=parts.sample,
        aligner=parts.aligner,
        deduper=parts.deduper,
        caller=read_set,
        stage=parts.stage,
    )


def parse_variant_parts(path: Path, token: str = "snv") -> StageParts:
    parts = path_parts(path)
    try:
        align_idx = parts.index("align")
        token_idx = parts.index(token)
    except ValueError as exc:
        raise StagingError(f"could not parse {token} stage from {path}") from exc
    if align_idx < 1 or align_idx + 2 >= len(parts) or token_idx + 1 >= len(parts):
        raise StagingError(f"incomplete {token} stage path: {path}")
    return StageParts(
        sample=parts[align_idx - 1],
        aligner=parts[align_idx + 1],
        deduper=parts[align_idx + 2],
        caller=parts[token_idx + 1],
        stage=token,
    )


def parse_sequence_parts(path: Path) -> StageParts:
    parts = path_parts(path)
    try:
        idx = parts.index("seqqc")
    except ValueError as exc:
        raise StagingError(f"could not parse sequence stage from {path}") from exc
    if idx < 1:
        raise StagingError(f"incomplete sequence stage path: {path}")
    return StageParts(sample=parts[idx - 1], stage="sequence")


def detect_read_token(path: Path) -> str:
    name = path.name
    if re.search(r"(^|[._-])R1([._-]|$)", name):
        return "R1"
    if re.search(r"(^|[._-])R2([._-]|$)", name):
        return "R2"
    raise StagingError(f"could not determine read token from {path}")


def copy_rewritten_delimited(
    source: Path,
    dest: Path,
    *,
    base_sample: str,
    stage_sample: str,
    delimiter: str,
) -> None:
    if not source.is_file():
        raise StagingError(f"missing delimited source for rewrite: {source}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with source.open(newline="", encoding="utf-8") as in_handle, dest.open(
        "w", newline="", encoding="utf-8"
    ) as out_handle:
        reader = csv.reader(in_handle, delimiter=delimiter)
        writer = csv.writer(out_handle, delimiter=delimiter, lineterminator="\n")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise StagingError(f"empty delimited source for rewrite: {source}") from exc
        writer.writerow(header)
        for row in reader:
            fixed = [stage_sample if value == base_sample else value for value in row]
            if fixed:
                fixed[0] = stage_sample
            writer.writerow(fixed)


def copy_goleft_indexcov_roc(source: Path, dest: Path, parts: StageParts) -> None:
    if not source.is_file():
        raise StagingError(f"missing goleft ROC source for rewrite: {source}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with source.open(newline="", encoding="utf-8") as in_handle, dest.open(
        "w", newline="", encoding="utf-8"
    ) as out_handle:
        reader = csv.reader(in_handle, delimiter="\t")
        writer = csv.writer(out_handle, delimiter="\t", lineterminator="\n")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise StagingError(f"empty goleft ROC source: {source}") from exc
        if len(header) < 3:
            raise StagingError(f"goleft ROC lacks sample columns: {source}")
        sample_columns = [parts.stage_sample]
        if len(header) > 3:
            sample_columns.extend(
                f"{parts.stage_sample}.{idx}" for idx in range(2, len(header) - 1)
            )
        writer.writerow([*header[:2], *sample_columns])
        writer.writerows(reader)


def copy_goleft_indexcov_ped(source: Path, dest: Path, parts: StageParts) -> None:
    if not source.is_file():
        raise StagingError(f"missing goleft PED source for rewrite: {source}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with source.open(newline="", encoding="utf-8") as in_handle, dest.open(
        "w", newline="", encoding="utf-8"
    ) as out_handle:
        reader = csv.reader(in_handle, delimiter="\t")
        writer = csv.writer(out_handle, delimiter="\t", lineterminator="\n")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise StagingError(f"empty goleft PED source: {source}") from exc
        clean_header = [field.lstrip("#") for field in header]
        if "sample_id" not in clean_header:
            raise StagingError(f"goleft PED lacks sample_id column: {source}")
        sample_idx = clean_header.index("sample_id")
        writer.writerow(header)
        for row in reader:
            fixed = list(row)
            if sample_idx < len(fixed):
                fixed[sample_idx] = parts.stage_sample
            writer.writerow(fixed)


def stage_custom_tsv(stager: Stager, source: Path) -> None:
    rel = relative_or_name(source, stager.input_root)
    dest = stager.output_dir / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)
    module = custom_module_name(source)
    with dest.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            raise StagingError(f"custom MultiQC TSV has no header: {source}")
        if "Sample" not in reader.fieldnames:
            return
        for idx, row in enumerate(reader, start=2):
            sample = (row.get("Sample") or "").strip()
            if not sample:
                raise StagingError(f"blank Sample in {source} line {idx}")
            stager.add_manifest_sample_row(
                source,
                dest,
                sample=sample,
                module=module,
                stage="custom",
                base_sample=row.get("base_sample", ""),
                aligner=row.get("aligner", ""),
                deduper=row.get("deduper", ""),
                caller=row.get("snv_caller", row.get("sv_caller", "")),
                input_kind="custom_mqc_row",
                group_id=f"{source}:{sample}",
            )
            stage_native_sources_from_custom_row(stager, source, row)


def custom_module_name(source: Path) -> str:
    name = source.name
    for suffix in ("_mqc.tsv", ".mqc.tsv", "_mqc.csv", ".mqc.csv"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return source.stem


def relative_or_name(source: Path, input_root: Path) -> Path:
    try:
        return source.resolve().relative_to(input_root.resolve())
    except ValueError:
        return Path("other_reports") / source.name


def stage_native_sources_from_custom_row(
    stager: Stager, custom_source: Path, row: dict[str, str]
) -> None:
    if row.get("classifier") == "sourmash_gather":
        stage_sourmash_sources_from_custom_row(stager, custom_source, row)
        return

    if row.get("classifier") == "ganon2":
        stage_ganon2_sources_from_custom_row(stager, custom_source, row)
        return

    if row.get("annotation_tool") == "vep":
        stage_vep_summary_htmls(stager, row)
        return

    if row.get("peddy_prefix"):
        prefix = Path(row["peddy_prefix"])
        sample = row.get("base_sample") or row.get("Sample", "").split(".")[0]
        parts = StageParts(
            sample=sample,
            aligner=row.get("aligner", ""),
            deduper=row.get("deduper", ""),
            caller=row.get("snv_caller", ""),
            stage="snv",
        )
        stage_peddy_prefix(stager, prefix, parts)
        return

    source_path = row.get("source_path", "").strip()
    if not source_path:
        return
    source = Path(source_path)
    custom_group = f"{custom_source}:{row.get('Sample', '')}"
    if source.name.endswith(".bcfstats.tsv"):
        parts = parse_variant_parts(source, "snv")
        stager.copy_file(
            source,
            Path("native/bcftools") / f"{parts.stage_sample}.bcfstats.tsv",
            parts,
            module="bcftools_stats",
            input_kind="bcftools_stats",
            group_id=custom_group,
        )
    elif source.name.endswith(".rtg.vcfstats.txt"):
        parts = parse_variant_parts(source, "snv")
        stager.copy_file(
            source,
            Path("native/rtg_vcfstats") / f"{parts.stage_sample}.rtg.vcfstats.txt",
            parts,
            module="rtg_vcfstats",
            input_kind="rtg_vcfstats",
            group_id=custom_group,
        )
    elif source.name.endswith(".tiddit.sv.summary.tsv"):
        parts = parse_variant_parts(source, "sv")
        stager.copy_file(
            source,
            Path("native/tiddit") / f"{parts.stage_sample}.tiddit.sv.summary.tsv",
            parts,
            module="tiddit",
            input_kind="tiddit_summary",
            group_id=custom_group,
        )


def stage_ganon2_sources_from_custom_row(
    stager: Stager, custom_source: Path, row: dict[str, str]
) -> None:
    report_value = row.get("ganon2_report", "").strip()
    rep_value = row.get("ganon2_rep", "").strip()
    if not report_value:
        raise StagingError(f"Ganon2 custom row is missing ganon2_report: {custom_source}")
    if not rep_value:
        raise StagingError(f"Ganon2 custom row is missing ganon2_rep: {custom_source}")
    report = Path(report_value)
    rep = Path(rep_value)
    row_read_set = row.get("read_set", "").strip()
    path_read_set = detect_metagenomics_read_set(report)
    if row_read_set != path_read_set:
        raise StagingError(
            f"Ganon2 read_set mismatch for {custom_source}: "
            f"row={row_read_set!r} path={path_read_set!r}"
        )
    parts = with_metagenomics_read_set(parse_alignment_parts(report), row_read_set)
    custom_group = f"{custom_source}:{row.get('Sample', '')}"
    for source, suffix, input_kind in (
        (report, ".ganon2.quick.tre", "ganon2_tree_report"),
        (rep, ".ganon2.quick.rep", "ganon2_rep"),
    ):
        stager.copy_file(
            source,
            Path("native/ganon2") / f"{parts.stage_sample}{suffix}",
            parts,
            module="ganon2",
            input_kind=input_kind,
            group_id=custom_group,
        )


def stage_sourmash_sources_from_custom_row(
    stager: Stager, custom_source: Path, row: dict[str, str]
) -> None:
    signature_value = row.get("sourmash_signature", "").strip()
    gather_value = row.get("sourmash_gather_csv", "").strip()
    if not signature_value:
        raise StagingError(
            f"sourmash custom row is missing sourmash_signature: {custom_source}"
        )
    if not gather_value:
        raise StagingError(
            f"sourmash custom row is missing sourmash_gather_csv: {custom_source}"
        )
    signature = Path(signature_value)
    gather_csv = Path(gather_value)
    row_read_set = row.get("read_set", "").strip()
    path_read_set = detect_metagenomics_read_set(gather_csv)
    if row_read_set != path_read_set:
        raise StagingError(
            f"sourmash read_set mismatch for {custom_source}: "
            f"row={row_read_set!r} path={path_read_set!r}"
        )
    parts = with_metagenomics_read_set(parse_alignment_parts(gather_csv), row_read_set)
    custom_group = f"{custom_source}:{row.get('Sample', '')}"
    for source, suffix, input_kind in (
        (signature, ".sourmash.sig", "sourmash_signature"),
        (gather_csv, ".sourmash.gather.csv", "sourmash_gather_csv"),
    ):
        stager.copy_file(
            source,
            Path("native/sourmash") / f"{parts.stage_sample}{suffix}",
            parts,
            module="sourmash",
            input_kind=input_kind,
            group_id=custom_group,
        )


def stage_vep_summary_htmls(stager: Stager, row: dict[str, str]) -> None:
    summary_glob = row.get("summary_glob", "").strip()
    if not summary_glob:
        raise StagingError(
            "VEP annotation row is missing summary_glob; regenerate vep_annotation_mqc.tsv"
        )
    vcf_gz = row.get("vcf_gz", "").strip()
    if not vcf_gz:
        raise StagingError("VEP annotation row is missing vcf_gz")
    vcf_path = Path(vcf_gz)
    if not vcf_path.is_file():
        raise StagingError(f"missing VEP VCF for native summary staging: {vcf_path}")
    parts = parse_variant_parts(vcf_path, "snv")
    summary_paths = [Path(path) for path in sorted(glob.glob(summary_glob))]
    if not summary_paths:
        raise StagingError(f"no VEP summary HTML files matched: {summary_glob}")
    for summary_path in summary_paths:
        stager.copy_file(
            summary_path,
            Path("native/vep") / parts.stage_sample / summary_path.name,
            StageParts(sample=summary_path.name.removesuffix("_summary.html"), stage="snv"),
            module="vep",
            input_kind="vep_summary_html",
            group_id=str(summary_path),
        )


def stage_peddy_prefix(stager: Stager, prefix: Path, parts: StageParts) -> None:
    group_id = str(prefix)
    out_dir = Path("native/peddy") / parts.stage_sample
    for suffix in ("sex_check.csv", "het_check.csv", "ped_check.csv"):
        source = Path(str(prefix) + suffix)
        dest = stager.output_dir / out_dir / f"{parts.stage_sample}.peddy.{suffix}"
        copy_rewritten_delimited(
            source,
            dest,
            base_sample=parts.sample,
            stage_sample=parts.stage_sample,
            delimiter=",",
        )
        stager.add_manifest_row(
            source,
            dest,
            parts,
            module="peddy",
            input_kind=f"peddy_{suffix}",
            group_id=group_id,
        )


def stage_fastqc_done(stager: Stager, source: Path) -> None:
    parts = parse_sequence_parts(source)
    source_dir = source.parent
    candidates = [
        path
        for path in sorted(source_dir.iterdir())
        if path.is_file()
        and (path.name.endswith("_fastqc.zip") or path.name.endswith("_fastqc.html"))
    ]
    if not candidates:
        raise StagingError(f"no FastQC native outputs beside {source}")
    for candidate in candidates:
        read = detect_read_token(candidate)
        read_parts = StageParts(sample=parts.sample, caller=read, stage="sequence")
        suffix = "_fastqc.zip" if candidate.name.endswith(".zip") else "_fastqc.html"
        stager.copy_file(
            candidate,
            Path("native/fastqc") / f"{parts.sample}.{read}{suffix}",
            read_parts,
            module="fastqc",
            input_kind=f"fastqc_{read}",
            group_id=f"fastqc:{parts.sample}:{read}",
        )


def stage_samtools_done(stager: Stager, source: Path) -> None:
    parts = parse_alignment_parts(source)
    metrics_dir = source.parent
    for suffix, module, kind in (
        (".stats.tsv", "samtools_stats", "samtools_stats"),
        (".flagstat.tsv", "samtools_flagstat", "samtools_flagstat"),
        (".idxstat.tsv", "samtools_idxstats", "samtools_idxstats"),
    ):
        metric = metrics_dir / f"{parts.stage_sample}{suffix}"
        stager.copy_file(
            metric,
            Path("native/samtools") / metric.name,
            parts,
            module=module,
            input_kind=kind,
            group_id=str(metric),
        )


def stage_picard_done(stager: Stager, source: Path) -> None:
    parts = parse_alignment_parts(source)
    picard_dir = source.parent.parent
    expected_suffixes = (
        ".alignment_summary_metrics.txt",
        ".insert_size_metrics.txt",
        ".quality_yield_metrics.txt",
        ".quality_distribution_metrics.txt",
        ".gc_bias.summary_metrics.txt",
        ".gc_bias.detail_metrics.txt",
    )
    copied = 0
    for suffix in expected_suffixes:
        metric = picard_dir / f"{parts.stage_sample}{suffix}"
        if metric.exists():
            stager.copy_file(
                metric,
                Path("native/picard") / metric.name,
                parts,
                module=f"picard{suffix.removesuffix('.txt')}",
                input_kind="picard_metric",
                group_id=str(metric),
            )
            copied += 1
    if copied == 0:
        raise StagingError(f"no Picard metrics found for {source}")


def stage_qualimap_done(stager: Stager, source: Path) -> None:
    parts = parse_alignment_parts(source)
    stager.copy_tree_files(
        source.parent,
        Path("native/qualimap") / parts.stage_sample,
        parts,
        module="qualimap",
        input_kind="qualimap_bamqc",
        group_id=str(source.parent),
    )


def stage_mosdepth_summary(stager: Stager, source: Path) -> None:
    parts = parse_alignment_parts(source)
    prefix = source.with_name(source.name.removesuffix(".mosdepth.summary.txt"))
    for suffix, input_kind in (
        (".mosdepth.summary.txt", "mosdepth_summary"),
        (".mosdepth.region.dist.txt", "mosdepth_region_dist"),
    ):
        metric = Path(str(prefix) + suffix)
        stager.copy_file(
            metric,
            Path("native/mosdepth") / metric.name,
            parts,
            module="mosdepth",
            input_kind=input_kind,
            group_id=str(source),
        )


def stage_kraken2_report(stager: Stager, source: Path) -> None:
    read_set = detect_metagenomics_read_set(source)
    parts = with_metagenomics_read_set(parse_alignment_parts(source), read_set)
    stager.copy_file(
        source,
        Path("native/kraken") / f"{parts.stage_sample}.kraken2.quick.report.txt",
        parts,
        module="kraken",
        input_kind="kraken2_report",
        group_id=str(source),
    )


def stage_goleft_done(stager: Stager, source: Path) -> None:
    parts = parse_alignment_parts(source)
    goleft_dir = source.parent / "goleft"
    if not goleft_dir.is_dir():
        raise StagingError(f"missing MultiQC source directory: {goleft_dir}")
    copied = 0
    for metric in sorted(goleft_dir.iterdir()):
        if not metric.is_file():
            continue
        if not metric.name.startswith("goleft-indexcov."):
            continue
        suffix = metric.name.removeprefix("goleft-indexcov")
        dest = (
            stager.output_dir
            / "native/goleft_indexcov"
            / parts.stage_sample
            / f"{parts.stage_sample}-indexcov{suffix}"
        )
        if suffix == ".roc":
            copy_goleft_indexcov_roc(metric, dest, parts)
            input_kind = "goleft_indexcov_roc"
        elif suffix == ".ped":
            copy_goleft_indexcov_ped(metric, dest, parts)
            input_kind = "goleft_indexcov_ped"
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(metric, dest)
            input_kind = f"goleft_indexcov{suffix}"
        stager.add_manifest_row(
            metric,
            dest,
            parts,
            module="goleft_indexcov",
            input_kind=input_kind,
            group_id=str(goleft_dir),
        )
        copied += 1
    if copied == 0:
        raise StagingError(f"no goleft indexcov files found in {goleft_dir}")


def stage_verifybamid_tsv(stager: Stager, source: Path) -> None:
    parts = parse_alignment_parts(source)
    panel = source.name.removesuffix(".vb2.tsv").split(".")[-1]
    stage_parts = StageParts(
        sample=parts.sample,
        aligner=parts.aligner,
        deduper=parts.deduper,
        caller=panel,
        stage="alignment",
    )
    selfsm = source.with_suffix("").with_suffix(".selfSM")
    if not selfsm.exists():
        selfsm = source.with_name(source.name.removesuffix(".tsv") + ".selfSM")
    if not selfsm.exists():
        raise StagingError(f"missing VerifyBamID selfSM beside {source}")
    dest = (
        stager.output_dir
        / "native/verifybamid"
        / f"{stage_parts.stage_sample}.selfSM"
    )
    copy_rewritten_delimited(
        selfsm,
        dest,
        base_sample=parts.sample,
        stage_sample=stage_parts.stage_sample,
        delimiter="\t",
    )
    stager.add_manifest_row(
        selfsm,
        dest,
        stage_parts,
        module="verifybamid",
        input_kind="verifybamid_selfSM",
        group_id=str(selfsm),
    )


def stage_somalier_extract(stager: Stager, source: Path) -> None:
    parts = path_parts(source)
    try:
        relatedness_idx = parts.index("relatedness")
        aligner = parts[relatedness_idx + 1]
        deduper = parts[relatedness_idx + 2]
    except (ValueError, IndexError) as exc:
        raise StagingError(f"could not parse Somalier relatedness path: {source}") from exc
    sample = source.name.removesuffix(".somalier")
    stage_parts = StageParts(
        sample=sample, aligner=aligner, deduper=deduper, stage="alignment"
    )
    stager.copy_file(
        source,
        Path("native/somalier") / f"{stage_parts.stage_sample}.somalier",
        stage_parts,
        module="somalier",
        input_kind="somalier_extract",
        group_id=str(source),
    )


def parse_relatedness_parts(path: Path) -> tuple[str, str]:
    parts = path_parts(path)
    try:
        relatedness_idx = parts.index("relatedness")
        aligner = parts[relatedness_idx + 1]
        deduper = parts[relatedness_idx + 2]
    except (ValueError, IndexError) as exc:
        raise StagingError(f"could not parse Somalier relatedness path: {path}") from exc
    return aligner, deduper


def rewrite_somalier_cohort(source: Path, dest: Path, aligner: str, deduper: str) -> list[str]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with source.open(newline="", encoding="utf-8") as in_handle:
        reader = csv.reader(in_handle, delimiter="\t")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise StagingError(f"empty Somalier cohort file: {source}") from exc
        rows = list(reader)

    clean_header = [field.lstrip("#") for field in header]
    sample_indexes = [
        idx
        for idx, field in enumerate(clean_header)
        if field in {"sample_id", "sample_a", "sample_b"}
    ]
    if not sample_indexes:
        raise StagingError(f"Somalier cohort file lacks sample columns: {source}")

    sample_map: dict[str, str] = {}
    for row in rows:
        for idx in sample_indexes:
            if idx < len(row) and row[idx]:
                sample_map[row[idx]] = f"{row[idx]}.{aligner}.{deduper}"

    staged_samples: list[str] = []
    with dest.open("w", newline="", encoding="utf-8") as out_handle:
        writer = csv.writer(out_handle, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        for row in rows:
            rewritten = [sample_map.get(value, value) for value in row]
            writer.writerow(rewritten)
            if "sample_id" in clean_header:
                sample_idx = clean_header.index("sample_id")
                staged_samples.append(rewritten[sample_idx])
            else:
                sample_a_idx = clean_header.index("sample_a")
                sample_b_idx = clean_header.index("sample_b")
                staged_samples.append(
                    f"{rewritten[sample_a_idx]}*{rewritten[sample_b_idx]}"
                )
    return staged_samples


def stage_somalier_cohort(stager: Stager, source: Path) -> None:
    aligner, deduper = parse_relatedness_parts(source)
    dest = stager.output_dir / "native/somalier" / f"{aligner}.{deduper}" / source.name
    staged_samples = rewrite_somalier_cohort(source, dest, aligner, deduper)
    for idx, sample in enumerate(staged_samples, start=2):
        stager.add_manifest_sample_row(
            source,
            dest,
            sample=sample,
            module="somalier",
            stage="alignment",
            aligner=aligner,
            deduper=deduper,
            input_kind=source.name,
            group_id=f"{source}:{idx}",
        )


def parse_contam_identity_batch_parts(path: Path) -> StageParts:
    parts = path_parts(path)
    try:
        idx = parts.index("contam_identity")
        aligner = parts[idx + 1]
        deduper = parts[idx + 2]
    except (ValueError, IndexError) as exc:
        raise StagingError(f"could not parse contam_identity batch path: {path}") from exc
    return StageParts(sample="cohort", aligner=aligner, deduper=deduper, stage="alignment")


def stage_ngstroublefinder_native(stager: Stager, source: Path) -> None:
    parts = parse_contam_identity_batch_parts(source)
    rel_name = f"{parts.aligner}.{parts.deduper}.{source.name}"
    stager.copy_file(
        source,
        Path("native/ngstroublefinder") / rel_name,
        parts,
        module="ngstroublefinder",
        input_kind=source.name,
        group_id=str(source.parent),
    )


def stage_haplocheck_native(stager: Stager, source: Path) -> None:
    if "/snv/" in source.as_posix():
        parts = parse_variant_parts(source)
    else:
        parts = parse_alignment_parts(source)
    stager.copy_file(
        source,
        Path("native/haplocheck") / parts.stage_sample / source.name,
        parts,
        module="haplocheck_native",
        input_kind=source.name,
        group_id=str(source.parent),
    )


def stage_read_haps_native(stager: Stager, source: Path) -> None:
    parts = parse_variant_parts(source)
    stager.copy_file(
        source,
        Path("native/read_haps") / parts.stage_sample / source.name,
        parts,
        module="read_haps_native",
        input_kind="read_haps",
        group_id=str(source),
    )


def stage_known_input(stager: Stager, source: Path) -> None:
    name = source.name
    if name.endswith("_mqc.tsv") or name.endswith(".mqc.tsv"):
        stage_custom_tsv(stager, source)
    elif (
        name in {"qcReport.tsv", "report.html"}
        and "/contam_identity/" in source.as_posix()
        and "/ngstroublefinder/" in source.as_posix()
    ):
        stage_ngstroublefinder_native(stager, source)
    elif (
        name.endswith(".haplocheck.contamination.txt")
        or name.endswith(".haplocheck.contamination.raw.txt")
        or name.endswith(".haplocheck.report.html")
    ):
        stage_haplocheck_native(stager, source)
    elif name.endswith(".read_haps.txt") and "/contam_identity/read_haps/" in source.as_posix():
        stage_read_haps_native(stager, source)
    elif name.endswith(".fastqc.done"):
        stage_fastqc_done(stager, source)
    elif name.endswith(".complete") and "/samtmetrics/" in source.as_posix():
        stage_samtools_done(stager, source)
    elif name.endswith(".done") and "/alignqc/picard/picard/" in source.as_posix():
        stage_picard_done(stager, source)
    elif name.endswith(".qmap.done"):
        stage_qualimap_done(stager, source)
    elif name.endswith(".mosdepth.summary.txt"):
        stage_mosdepth_summary(stager, source)
    elif (
        name.endswith(".kraken2.quick.report.txt")
        and "/unmapped_metagenomics/" in source.as_posix()
    ):
        stage_kraken2_report(stager, source)
    elif name == "goleft.done":
        stage_goleft_done(stager, source)
    elif name in {"cohort.samples.tsv", "cohort.pairs.tsv"} and "/somalier/" in source.as_posix():
        stage_somalier_cohort(stager, source)
    elif name.endswith(".somalier"):
        stage_somalier_extract(stager, source)
    elif name.endswith(".done") or name.endswith(".html") or name.endswith(".json"):
        return
    else:
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("inputs", nargs="+")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    stager = Stager(
        input_root=Path(args.input_root),
        output_dir=Path(args.output_dir),
        manifest=Path(args.manifest),
    )
    stager.reset()
    for raw in args.inputs:
        source = Path(raw)
        if not source.exists():
            raise StagingError(f"missing declared MultiQC component input: {source}")
        stage_known_input(stager, source)
    stager.finish()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
