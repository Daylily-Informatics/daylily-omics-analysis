#!/usr/bin/env python3
"""Audit BAM/CRAM-producing alignment paths for read preservation contracts."""

from __future__ import annotations

import argparse
import csv
import gzip
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SECONDARY_OR_SUPPLEMENTARY = 0x100 | 0x800
READ1 = 0x40
READ2 = 0x80


class AuditError(RuntimeError):
    """Raised for preservation-contract failures."""


@dataclass
class ProducerAudit:
    rule: str
    file: str
    output_kind: str
    input_kind: str
    scope: str
    status: str
    evidence: str
    action: str


@dataclass(frozen=True)
class ReadKey:
    qname: str
    read_number: str


def _read_text(repo_root: Path, relpath: str) -> str:
    return (repo_root / relpath).read_text(encoding="utf-8")


def _tokens(value: str) -> list[str]:
    return shlex.split(value or "")


def _has_token(value: str, token: str) -> bool:
    return token in _tokens(value)


def _extract_config_scalar(config_path: Path, section: str, key: str) -> str:
    lines = config_path.read_text(encoding="utf-8").splitlines()
    in_section = False
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if re.match(r"^\S", line):
            in_section = line.split(":", 1)[0].strip() == section
            continue
        if in_section:
            match = re.match(rf"^\s+{re.escape(key)}:\s*(.*?)\s*(?:#.*)?$", line)
            if match:
                raw_value = match.group(1).strip()
                if (
                    len(raw_value) >= 2
                    and raw_value[0] == raw_value[-1]
                    and raw_value[0] in {'"', "'"}
                ):
                    return raw_value[1:-1]
                return raw_value
    raise AuditError(f"missing config key {section}.{key} in {config_path}")


def _check_bwa_opts(repo_root: Path, section: str, key: str = "bwa_opts") -> list[str]:
    problems: list[str] = []
    for profile in ("local", "slurm"):
        config_path = repo_root / "config" / "day_profiles" / profile / "templates" / "rule_config.yaml"
        opts = _extract_config_scalar(config_path, section, key)
        if not _has_token(opts, "-Y"):
            problems.append(f"{config_path}:{section}.{key} missing -Y")
        if _has_token(opts, "-H"):
            problems.append(f"{config_path}:{section}.{key} contains hard-clipping -H")
    return problems


def _check_minimap2_opts(repo_root: Path, section: str) -> list[str]:
    problems: list[str] = []
    for profile in ("local", "slurm"):
        config_path = repo_root / "config" / "day_profiles" / profile / "templates" / "rule_config.yaml"
        opts = _extract_config_scalar(config_path, section, "minimap2_opts")
        if not _has_token(opts, "-Y"):
            problems.append(f"{config_path}:{section}.minimap2_opts missing -Y")
        if not _has_token(opts, "--secondary-seq"):
            problems.append(
                f"{config_path}:{section}.minimap2_opts missing --secondary-seq"
            )
        if _has_token(opts, "--sam-hit-only"):
            problems.append(
                f"{config_path}:{section}.minimap2_opts contains --sam-hit-only"
            )
    return problems


def _check_strobe_opts(repo_root: Path) -> list[str]:
    problems: list[str] = []
    for profile in ("local", "slurm"):
        config_path = repo_root / "config" / "day_profiles" / profile / "templates" / "rule_config.yaml"
        opts = _extract_config_scalar(config_path, "strobe_align_sort", "strobe_opts")
        if _has_token(opts, "-x"):
            problems.append(f"{config_path}:strobe_align_sort.strobe_opts contains -x")
        if _has_token(opts, "-U"):
            problems.append(f"{config_path}:strobe_align_sort.strobe_opts contains -U")
    return problems


def _contains_any(text: str, patterns: Iterable[str]) -> bool:
    return any(pattern in text for pattern in patterns)


def _dedup_removal_problems(text: str, label: str) -> list[str]:
    banned_patterns = (
        "REMOVE_DUPLICATES=true",
        "remove_duplicates=true",
        "--remove-duplicates",
        "--remove_duplicates",
        "--remove-dups",
        " rmdup ",
    )
    return [f"{label} contains duplicate-removal pattern {pattern}" for pattern in banned_patterns if pattern in text]


def _samtools_view_filter_problems(text: str, label: str) -> list[str]:
    banned_patterns = (" -F ", "\n            -F ", " -f ", "\n            -f ", " -q ", " -L ", " --subsample ", " -s ")
    commands = re.findall(r"samtools\s+view\b.*?;", text, flags=re.S)
    return [
        f"{label} contains full-sample samtools view filtering pattern {pattern.strip()}"
        for command in commands
        for pattern in banned_patterns
        if pattern in command
    ]


def _static_records(repo_root: Path) -> list[ProducerAudit]:
    records: list[ProducerAudit] = []

    bwa_problems = _check_bwa_opts(repo_root, "bwa_mem2a_aln_sort")
    bwa_rule = _read_text(repo_root, "workflow/rules/bwa_mem2a_align_sort.smk")
    if _contains_any(bwa_rule, ("samtools view -F", "samtools view -f", "samtools view -q")):
        bwa_problems.append("bwa_mem2_sort shell contains a samtools filtering flag")
    records.append(
        ProducerAudit(
            "bwa_mem2_sort",
            "workflow/rules/bwa_mem2a_align_sort.smk",
            "BAM",
            "FASTQ",
            "full_sample_alignment",
            "fail" if bwa_problems else "pass",
            "; ".join(bwa_problems) if bwa_problems else "bwa opts include -Y and no read-filtering flags were found",
            "fix BWA options or remove filtering flags" if bwa_problems else "none",
        )
    )

    sent_bwa_problems = _check_bwa_opts(repo_root, "sentieon", "sent_opts")
    sent_bwa_problems.extend(_check_bwa_opts(repo_root, "sentieon_cgt7p", "sent_opts"))
    records.append(
        ProducerAudit(
            "sentieon_bwa_sort / sentieon_cgt7p_bwa_sort",
            "workflow/rules/sentieon.smk",
            "BAM",
            "FASTQ",
            "full_sample_alignment",
            "fail" if sent_bwa_problems else "needs_empirical_check",
            "; ".join(sent_bwa_problems)
            if sent_bwa_problems
            else "Sentieon BWA opts include -Y; closed-source sort/alignment path still needs count and sequence proof",
            "run representative empirical QNAME/count/SEQ checks",
        )
    )

    strobe_problems = _check_strobe_opts(repo_root)
    strobe_rule = _read_text(repo_root, "workflow/rules/strobe_align_sort.smk")
    if "samtools view" not in strobe_rule or "-c -f 0x900" not in strobe_rule:
        strobe_problems.append("strobe CRAM-to-FASTQ path lacks secondary/supplementary guard")
    records.append(
        ProducerAudit(
            "strobe_align_sort_bam",
            "workflow/rules/strobe_align_sort.smk",
            "BAM",
            "FASTQ",
            "full_sample_alignment",
            "fail" if strobe_problems else "pass",
            "; ".join(strobe_problems)
            if strobe_problems
            else "strobealign opts do not suppress unmapped reads; CRAM extraction path is guarded",
            "fix strobe options or CRAM extraction guard" if strobe_problems else "none",
        )
    )
    records.append(
        ProducerAudit(
            "strobe_align_sort_cram",
            "workflow/rules/strobe_align_sort.smk",
            "BAM",
            "CRAM",
            "alternate_full_sample_alignment",
            "needs_empirical_check" if not strobe_problems else "fail",
            "DAY_STROBE_TOGGLE path reconstitutes FASTQ from CRAM; guard exists but tool behavior should be measured",
            "run representative CRAM-to-strobe empirical QNAME/count/SEQ checks",
        )
    )

    for section, rule_name, path in (
        ("sentmm2_align_sort", "sentmm2_align_sort", "workflow/rules/sentmm2_align_sort.smk"),
        (
            "sentmm2ont_align_sort",
            "sentmm2ont_align_sort",
            "workflow/rules/sentmm2ont_align_sort.smk",
        ),
    ):
        problems = _check_minimap2_opts(repo_root, section)
        rule_text = _read_text(repo_root, path)
        if "samtools view -c -f 0x900" not in rule_text:
            problems.append(f"{rule_name} lacks uBAM secondary/supplementary guard")
        if "samtools fastq -@ 4 -F 0x900 -T MM,ML" not in rule_text:
            problems.append(f"{rule_name} does not make samtools fastq -F 0x900 explicit")
        records.append(
            ProducerAudit(
                rule_name,
                path,
                "CRAM",
                "FASTQ/uBAM",
                "full_sample_alignment",
                "fail" if problems else "pass",
                "; ".join(problems)
                if problems
                else "minimap2 opts include -Y --secondary-seq and uBAM extraction is guarded",
                "fix minimap2 opts or uBAM extraction guard" if problems else "none",
            )
        )

    doppel_problems = _dedup_removal_problems(
        _read_text(repo_root, "workflow/rules/doppel_mrkdups.smk"),
        "doppelmark_dups",
    )
    sent_dedup_problems = _dedup_removal_problems(
        _read_text(repo_root, "workflow/rules/sentieon_markdups.smk"),
        "sent_dedup",
    )
    no_dedup_problems = _samtools_view_filter_problems(
        _read_text(repo_root, "workflow/rules/no_dedup.smk"),
        "no_dedup",
    )

    records.extend(
        [
            ProducerAudit(
                "pre_prep_ultima_cram / pre_prep_ont_cram / pre_prep_pb_cram / pre_prep_roche_bam",
                "workflow/rules/prep_input_sample_files.smk",
                "BAM/CRAM",
                "manifest BAM/CRAM",
                "staged_full_sample_input",
                "pass",
                "copy/symlink staging is full-sample; manifest downsample settings are explicit pre-alignment transforms",
                "report downsample settings as intentional read-set changes",
            ),
            ProducerAudit(
                "merge_bam",
                "workflow/rules/merge_all_bams.smk",
                "BAM",
                "lane BAMs",
                "full_sample_merge",
                "needs_empirical_check",
                "sambamba merge/sort has no visible filters; merged count should equal lane-count sum",
                "compare pre/post total and primary record counts",
            ),
            ProducerAudit(
                "doppelmark_dups",
                "workflow/rules/doppel_mrkdups.smk",
                "CRAM",
                "BAM",
                "full_sample_dedup",
                "fail" if doppel_problems else "needs_empirical_check",
                "; ".join(doppel_problems)
                if doppel_problems
                else "doppelmark command appears to mark duplicates, but closed/compiled behavior needs count proof",
                "remove duplicate-removal flags"
                if doppel_problems
                else "compare input/output total and primary counts and duplicate flags",
            ),
            ProducerAudit(
                "sent_dedup",
                "workflow/rules/sentieon_markdups.smk",
                "CRAM",
                "BAM",
                "full_sample_dedup",
                "fail" if sent_dedup_problems else "needs_empirical_check",
                "; ".join(sent_dedup_problems)
                if sent_dedup_problems
                else "Sentieon Dedup has no remove flag in the rule; closed-source behavior needs count proof",
                "remove duplicate-removal flags"
                if sent_dedup_problems
                else "compare input/output total and primary counts and duplicate flags",
            ),
            ProducerAudit(
                "no_dedup",
                "workflow/rules/no_dedup.smk",
                "CRAM",
                "BAM",
                "full_sample_no_dedup",
                "fail" if no_dedup_problems else "pass",
                "; ".join(no_dedup_problems)
                if no_dedup_problems
                else "samtools view conversion uses -C -T and --write-index without filtering flags",
                "remove filtering flags" if no_dedup_problems else "none",
            ),
            ProducerAudit(
                "no_dedup_cram / no_dedup_roche_bam",
                "workflow/rules/no_dedup_cram.smk; workflow/rules/roche_sbxd.smk",
                "BAM/CRAM",
                "BAM/CRAM",
                "full_sample_no_dedup",
                "pass",
                "relative symlink passthrough; no read transform",
                "none",
            ),
            ProducerAudit(
                "sentieon_gatk_bsqr",
                "workflow/rules/sentieon_new_gatk.smk",
                "CRAM",
                "CRAM",
                "full_sample_recalibration",
                "needs_empirical_check",
                "ReadWriter applies BQSR to a full-sample CRAM; read count and SEQ preservation should be measured",
                "compare input/output counts and hard clips",
            ),
            ProducerAudit(
                "aiv_bams / mutect2_bams / varn_bams",
                "workflow/rules/aivariant.smk; workflow/rules/mutect2.smk; workflow/rules/varnet.smk",
                "BAM",
                "CRAM",
                "variant_caller_region_slice",
                "intentional_subset",
                "rules use samtools view with explicit chromosome/region windows for caller-local BAMs",
                "exclude from full-sample preservation enforcement",
            ),
            ProducerAudit(
                "expansionhunter_call / roche_gatk_haplotypecaller / lfq2_indelqual",
                "workflow/rules/expansionhunter.smk; workflow/rules/roche_sbxd.smk; workflow/rules/lofreq2.smk",
                "BAM/CRAM",
                "BAM/CRAM",
                "caller_internal_alignment_artifact",
                "intentional_subset",
                "caller-specific realigned/bamout/indelqual artifacts are not full-sample alignment products",
                "inventory only unless promoted to a final alignment product",
            ),
            ProducerAudit(
                "sent_hybrid_* temporary BAM stages",
                "workflow/rules/sent_hybrid_*.smk",
                "BAM",
                "BAM/CRAM/FASTQ",
                "hybrid_caller_intermediate",
                "out_of_scope_intermediate",
                "hybrid rules emit synthetic stage BAMs and caller-internal partitions",
                "inventory only; add separate contracts if these become deliverables",
            ),
        ]
    )
    return records


def _write_tsv(records: list[ProducerAudit], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(
            ["rule", "file", "output_kind", "input_kind", "scope", "status", "evidence", "action"]
        )
        for record in records:
            writer.writerow(
                [
                    record.rule,
                    record.file,
                    record.output_kind,
                    record.input_kind,
                    record.scope,
                    record.status,
                    record.evidence,
                    record.action,
                ]
            )


def _write_markdown(records: list[ProducerAudit], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    counts: dict[str, int] = {}
    for record in records:
        counts[record.status] = counts.get(record.status, 0) + 1
    lines = [
        "# Alignment BAM/CRAM Preservation Audit",
        "",
        "This report inventories BAM/CRAM producers and applies preservation contracts to full-sample alignment products.",
        "The invariant applies after explicit manifest-driven trim or downsample transforms.",
        "",
        "## Status Counts",
        "",
    ]
    for status in sorted(counts):
        lines.append(f"- {status}: {counts[status]}")
    lines.extend(
        [
            "",
            "## Producer Inventory",
            "",
            "| Rule | Scope | Status | Evidence | Action |",
            "| --- | --- | --- | --- | --- |",
        ]
    )
    for record in records:
        lines.append(
            "| {rule} | {scope} | {status} | {evidence} | {action} |".format(
                rule=record.rule.replace("|", "\\|"),
                scope=record.scope,
                status=record.status,
                evidence=record.evidence.replace("|", "\\|"),
                action=record.action.replace("|", "\\|"),
            )
        )
    lines.extend(
        [
            "",
            "## Empirical Checks To Run On Representative Outputs",
            "",
            "- Compare the transformed input QNAME/read-number set to output primary records.",
            "- Compare total and primary record counts before and after merge/dedup/recalibration.",
            "- Assert every emitted BAM/CRAM record has materialized SEQ and no hard-clipped CIGAR.",
            "- Fail uBAM/CRAM-to-FASTQ extraction when secondary or supplementary records are present before extraction.",
            "",
        ]
    )
    output.write_text("\n".join(lines), encoding="utf-8")


def _open_text(path: Path):
    if path.suffix in {".gz", ".bgz"}:
        return gzip.open(path, "rt", encoding="utf-8")
    return path.open("r", encoding="utf-8")


def _normalize_fastq_name(name: str) -> str:
    first = name.strip().split()[0]
    if first.startswith("@"):
        first = first[1:]
    if first.endswith("/1") or first.endswith("/2"):
        return first[:-2]
    return first


def fastq_read_keys(path: Path, read_number: str) -> set[ReadKey]:
    keys: set[ReadKey] = set()
    with _open_text(path) as handle:
        while True:
            name = handle.readline()
            if not name:
                break
            seq = handle.readline()
            plus = handle.readline()
            qual = handle.readline()
            if not seq or not plus or not qual:
                raise AuditError(f"truncated FASTQ record in {path}")
            keys.add(ReadKey(_normalize_fastq_name(name), read_number))
    return keys


def _samtools_view_cmd(path: Path, reference: Path | None = None) -> list[str]:
    cmd = ["samtools", "view"]
    if reference is not None:
        cmd.extend(["-T", str(reference)])
    cmd.append(str(path))
    return cmd


def _iter_sam_records(path: Path, reference: Path | None = None) -> Iterable[list[str]]:
    proc = subprocess.Popen(
        _samtools_view_cmd(path, reference),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        if line.startswith("@"):
            continue
        yield line.rstrip("\n").split("\t")
    stderr = proc.stderr.read() if proc.stderr is not None else ""
    retcode = proc.wait()
    if retcode:
        raise AuditError(f"samtools view failed for {path}: {stderr.strip()}")


def _read_number_from_flag(flag: int) -> str:
    if flag & READ1:
        return "1"
    if flag & READ2:
        return "2"
    return "0"


def alignment_primary_read_keys(path: Path, reference: Path | None = None) -> set[ReadKey]:
    keys: set[ReadKey] = set()
    for fields in _iter_sam_records(path, reference):
        flag = int(fields[1])
        if flag & SECONDARY_OR_SUPPLEMENTARY:
            continue
        keys.add(ReadKey(fields[0], _read_number_from_flag(flag)))
    return keys


def alignment_record_counts(path: Path, reference: Path | None = None) -> dict[str, int]:
    counts = {"total": 0, "primary": 0, "missing_seq": 0, "hard_clipped": 0}
    for fields in _iter_sam_records(path, reference):
        counts["total"] += 1
        flag = int(fields[1])
        cigar = fields[5]
        seq = fields[9]
        if not flag & SECONDARY_OR_SUPPLEMENTARY:
            counts["primary"] += 1
        if seq == "*":
            counts["missing_seq"] += 1
        if "H" in cigar:
            counts["hard_clipped"] += 1
    return counts


def fail_if_secondary_or_supplementary(path: Path, reference: Path | None = None) -> None:
    cmd = ["samtools", "view", "-c", "-f", "0x900"]
    if reference is not None:
        cmd.extend(["-T", str(reference)])
    cmd.append(str(path))
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise AuditError(f"samtools secondary/supplementary count failed for {path}: {result.stderr.strip()}")
    count = int(result.stdout.strip() or "0")
    if count:
        raise AuditError(
            f"{path} contains {count} secondary/supplementary records before samtools fastq extraction"
        )


def validate_read_set(
    input_fastqs: list[tuple[Path, str]],
    output_alignment: Path,
    reference: Path | None,
) -> None:
    expected: set[ReadKey] = set()
    for fastq, read_number in input_fastqs:
        expected.update(fastq_read_keys(fastq, read_number))
    observed = alignment_primary_read_keys(output_alignment, reference)
    missing = expected - observed
    extra = observed - expected
    if missing or extra:
        raise AuditError(
            f"read-set mismatch for {output_alignment}: missing={len(missing)} extra={len(extra)}"
        )
    counts = alignment_record_counts(output_alignment, reference)
    if counts["missing_seq"] or counts["hard_clipped"]:
        raise AuditError(
            f"sequence reconstruction failure for {output_alignment}: "
            f"missing_seq={counts['missing_seq']} hard_clipped={counts['hard_clipped']}"
        )


def validate_dedup_counts(pre_alignment: Path, post_alignment: Path, reference: Path | None) -> None:
    pre = alignment_record_counts(pre_alignment, reference)
    post = alignment_record_counts(post_alignment, reference)
    if pre["total"] != post["total"] or pre["primary"] != post["primary"]:
        raise AuditError(
            "dedup count mismatch: "
            f"pre_total={pre['total']} post_total={post['total']} "
            f"pre_primary={pre['primary']} post_primary={post['primary']}"
        )
    if post["missing_seq"] or post["hard_clipped"]:
        raise AuditError(
            f"dedup output sequence reconstruction failure: missing_seq={post['missing_seq']} "
            f"hard_clipped={post['hard_clipped']}"
        )


def run_audit(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    records = _static_records(repo_root)
    _write_tsv(records, Path(args.out_tsv))
    _write_markdown(records, Path(args.out_md))
    failures = [record for record in records if record.status == "fail"]
    if failures:
        for failure in failures:
            print(f"FAIL {failure.rule}: {failure.evidence}", file=sys.stderr)
        return 1
    return 0


def run_validate_read_set(args: argparse.Namespace) -> int:
    reference = Path(args.reference).resolve() if args.reference else None
    fastqs = [(Path(item).resolve(), str(index + 1)) for index, item in enumerate(args.fastq)]
    validate_read_set(fastqs, Path(args.output_alignment).resolve(), reference)
    return 0


def run_validate_dedup(args: argparse.Namespace) -> int:
    reference = Path(args.reference).resolve() if args.reference else None
    validate_dedup_counts(
        Path(args.pre_alignment).resolve(),
        Path(args.post_alignment).resolve(),
        reference,
    )
    return 0


def run_guard_ubam(args: argparse.Namespace) -> int:
    reference = Path(args.reference).resolve() if args.reference else None
    fail_if_secondary_or_supplementary(Path(args.input_alignment).resolve(), reference)
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command")

    audit = subparsers.add_parser("audit", help="write static preservation audit report")
    audit.add_argument("--repo-root", default=".")
    audit.add_argument("--out-md", required=True)
    audit.add_argument("--out-tsv", required=True)
    audit.set_defaults(func=run_audit)

    read_set = subparsers.add_parser("validate-read-set", help="compare FASTQ reads to output primary alignments")
    read_set.add_argument("--fastq", action="append", required=True, help="input FASTQ after trim/downsample transform; pass once for single-end or twice for paired-end")
    read_set.add_argument("--output-alignment", required=True)
    read_set.add_argument("--reference", default="")
    read_set.set_defaults(func=run_validate_read_set)

    dedup = subparsers.add_parser("validate-dedup", help="compare pre/post dedup BAM/CRAM counts")
    dedup.add_argument("--pre-alignment", required=True)
    dedup.add_argument("--post-alignment", required=True)
    dedup.add_argument("--reference", default="")
    dedup.set_defaults(func=run_validate_dedup)

    guard = subparsers.add_parser("guard-ubam", help="fail if BAM/CRAM has secondary/supplementary records before samtools fastq")
    guard.add_argument("--input-alignment", required=True)
    guard.add_argument("--reference", default="")
    guard.set_defaults(func=run_guard_ubam)

    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.error("a subcommand is required")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        return args.func(args)
    except AuditError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
