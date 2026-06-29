from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_ROOT = REPO_ROOT / "workflow"
SNAKEFILE = WORKFLOW_ROOT / "Snakefile"

INCLUDE_RE = re.compile(r'^\s*include:\s*[rRuUbBfF]*["\']([^"\']+)["\']')
RESERVED_ASSIGNMENT_RE = re.compile(r"^\s*(module)\s*=", re.MULTILINE)
BARE_SENTIEON_CLI_PYTHON_LOOKUP_RE = re.compile(
    r"\bpython\s+-c\s+[\"'][^\"'\n]*sentieon_cli\.scripts"
)
RAW_SENTIEON_COMMAND_RE = re.compile(
    r"(?<![A-Za-z0-9_./-])(?:/[^ \t;|&<>]*sentieon|sentieon)\s+"
    r"(?:driver|bwa|util|pyexec)\b"
)
RAW_SENTIEON_CLI_COMMAND_RE = re.compile(
    r"(?<![A-Za-z0-9_./-])sentieon-cli\s+"
    r"(?:dnascope|dnascope-pangenome)\b"
)


def _resolve_include(current_file: Path, include_path: str) -> Path:
    candidates = (
        current_file.parent / include_path,
        WORKFLOW_ROOT / include_path,
        WORKFLOW_ROOT / "rules" / include_path,
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise AssertionError(f"Unable to resolve Snakemake include {include_path!r} from {current_file}")


def _active_snakemake_files() -> set[Path]:
    active: set[Path] = set()
    pending = [SNAKEFILE.resolve()]

    while pending:
        path = pending.pop()
        if path in active:
            continue
        active.add(path)
        text = path.read_text(encoding="utf-8")
        for line in text.splitlines():
            if line.lstrip().startswith("#"):
                continue
            match = INCLUDE_RE.match(line)
            if match:
                pending.append(_resolve_include(path, match.group(1)))

    return active


def test_active_snakemake_files_do_not_assign_reserved_module_directive() -> None:
    offenders: list[str] = []
    for path in sorted(_active_snakemake_files()):
        text = path.read_text(encoding="utf-8")
        for match in RESERVED_ASSIGNMENT_RE.finditer(text):
            line_no = text.count("\n", 0, match.start()) + 1
            offenders.append(f"{path.relative_to(REPO_ROOT)}:{line_no}: {match.group(0).strip()}")

    assert not offenders, "Reserved Snakemake directive assignment found:\n" + "\n".join(offenders)


def test_hybrid_rules_use_stdlib_importlib_resources() -> None:
    offenders: list[str] = []
    for path in sorted((WORKFLOW_ROOT / "rules").glob("*hybrid*modular*.smk")):
        text = path.read_text(encoding="utf-8")
        if "importlib_resources" in text:
            offenders.append(str(path.relative_to(REPO_ROOT)))

    assert not offenders, "Undeclared importlib_resources backport used:\n" + "\n".join(offenders)


def test_active_hybrid_rules_resolve_sentieon_cli_scripts_with_rule_env_python() -> None:
    offenders: list[str] = []
    for path in sorted(_active_snakemake_files()):
        if "hybrid" not in path.name:
            continue
        text = path.read_text(encoding="utf-8")
        for match in BARE_SENTIEON_CLI_PYTHON_LOOKUP_RE.finditer(text):
            line_no = text.count("\n", 0, match.start()) + 1
            offenders.append(f"{path.relative_to(REPO_ROOT)}:{line_no}: {match.group(0)}")

    assert not offenders, (
        "Active hybrid Sentieon CLI helper lookups must use $CONDA_PREFIX/bin/python:\n"
        + "\n".join(offenders)
    )


def test_active_sentieon_rules_route_executable_calls_through_jitter_wrappers() -> None:
    offenders: list[str] = []
    for path in sorted(_active_snakemake_files()):
        if "sent" not in path.name:
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            executable_part = line.split("#", 1)[0]
            if RAW_SENTIEON_COMMAND_RE.search(executable_part):
                offenders.append(f"{path.relative_to(REPO_ROOT)}:{line_no}: {line.strip()}")
            if RAW_SENTIEON_CLI_COMMAND_RE.search(executable_part):
                offenders.append(f"{path.relative_to(REPO_ROOT)}:{line_no}: {line.strip()}")

    assert not offenders, (
        "Active Sentieon executable calls must use bin/dayoa_sentieon or bin/dayoa_sentieon_cli:\n"
        + "\n".join(offenders)
    )


def test_sentdhiomr_stage1_handles_empty_merged_diff_beds() -> None:
    path = WORKFLOW_ROOT / "rules" / "sent_hybrid_ilmn_ont_modular.refactored.smk"
    text = path.read_text(encoding="utf-8")

    required_fragments = [
        "if [ ! -s {input.diff_bed} ]; then",
        "WARNING: merged_diff.bed is empty - no haplotype regions to process",
        "touch {output.hap_bed} {output.hap_vcf}",
        "--interval \"$scoped_diploid_bed\"",
        "No insertion output produced for empty merged_diff shard",
        "samtools quickcheck {output.hap_bam} {output.bam}",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in text]

    assert not missing, (
        "sentdhiomr_stage1 must tolerate valid empty merged_diff.bed shards:\n"
        + "\n".join(missing)
    )


def test_sentdhiomr_long_running_rules_use_four_hour_walltime_cap() -> None:
    path = WORKFLOW_ROOT / "rules" / "sent_hybrid_ilmn_ont_modular.refactored.smk"
    text = path.read_text(encoding="utf-8")

    required_fragments = [
        "time=config['sentdhiomr'].get('time_snv_long', 240)",
        "time=config['sentdhiomr'].get('time_snv_transfer', 240)",
        "time=config['sentdhiomr'].get('time_mito', 240)",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in text]

    assert not missing, (
        "Long-running sentdhiomr rules must keep the 240 minute Slurm time cap:\n"
        + "\n".join(missing)
    )


def test_sentdhiomr_late_stages_handle_empty_refined_regions() -> None:
    path = WORKFLOW_ROOT / "rules" / "sent_hybrid_ilmn_ont_modular.refactored.smk"
    text = path.read_text(encoding="utf-8")

    required_fragments = [
        "if [ ! -s {input.bed} ]; then",
        "WARNING: hybrid_stage2.bed is empty - no Stage 3 realignment regions; creating empty BAM",
        "Stage 3 completed with empty input regions",
        "initial_vcf=MDIR + \"{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz\"",
        "WARNING: hybrid_stage2.bed is empty - no Pass 2 regions; creating empty VCF",
        "bcftools view --threads {threads} -h {input.initial_vcf} | bgzip -c > {output.vcf}",
        "Pass 2 completed with empty input regions",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in text]

    assert not missing, (
        "sentdhiomr_stage3/pass2 must tolerate valid empty refined-region shards:\n"
        + "\n".join(missing)
    )


def test_sentdhuomr_stage1_uses_sequential_driver_outputs() -> None:
    path = WORKFLOW_ROOT / "rules" / "sent_hybrid_ug_ont_modular.refactored.smk"
    text = path.read_text(encoding="utf-8")

    required_fragments = [
        "Match sentieon-cli hybrid_stage1(): run HAP + INS drivers sequentially",
        'unset bwt_max_mem || true',
        'bin/dayoa_sentieon driver \\',
        '2>> {log} > "$TMPDIR/hap_stdout.sam"',
        '2>> {log} > "$TMPDIR/ins_stdout.sam"',
        'cat "$TMPDIR/hap_stdout.sam" "$TMPDIR/ins_stdout.sam"',
        "samtools quickcheck {output.hap_bam} {output.bam}",
    ]
    forbidden_fragments = [
        "cat <($HAP_CMD",
        "process substitutions",
        "wait",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in text]
    present_forbidden = [fragment for fragment in forbidden_fragments if fragment in text]

    assert not missing, "sentdhuomr_stage1 missing hard-failure fragments:\n" + "\n".join(missing)
    assert not present_forbidden, (
        "sentdhuomr_stage1 must not use process substitution:\n" + "\n".join(present_forbidden)
    )


def test_sentdhuomr_late_stages_handle_empty_refined_regions() -> None:
    path = WORKFLOW_ROOT / "rules" / "sent_hybrid_ug_ont_modular.refactored.smk"
    text = path.read_text(encoding="utf-8")

    required_fragments = [
        "WARNING: stage1_hap.bed is empty - no target haplotypes for Stage 2",
        "Stage 2 completed with empty target haplotypes",
        "if [ ! -s {input.bed} ]; then",
        "WARNING: hybrid_stage2.bed is empty - no Stage 3 realignment regions; creating empty BAM",
        "Stage 3 completed with empty input regions",
        "initial_vcf=MDIR + \"{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/initial.vcf.gz\"",
        "WARNING: hybrid_stage2.bed is empty - no Pass 2 regions; creating empty VCF",
        "bcftools view --threads {threads} -h {input.initial_vcf} | bgzip -c > {output.vcf}",
        "Pass 2 completed with empty input regions",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in text]

    assert not missing, (
        "sentdhuomr Stage2/Stage3/pass2 must tolerate empty target/refined-region shards:\n"
        + "\n".join(missing)
    )
