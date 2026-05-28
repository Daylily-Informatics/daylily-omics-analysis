from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from statistics import mean


class PipelineReportError(ValueError):
    """Raised when DayOA cannot write workflow provenance reports."""


RULE_RE = re.compile(r"^rule\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", re.MULTILINE)
SHELL_RE = re.compile(r"^\s*shell\s*:\s*(?P<body>.*?)(?=^\S|\Z)", re.MULTILINE | re.DOTALL)
COMMAND_TOKEN_RE = re.compile(r"(?<![A-Za-z0-9_./-])([A-Za-z][A-Za-z0-9_.+-]*)(?:\s|$)")
SAFE_VERSION_COMMANDS = {
    "bcftools": ("bcftools", "--version"),
    "bwa": ("bwa",),
    "fastqc": ("fastqc", "--version"),
    "multiqc": ("multiqc", "--version"),
    "python": ("python", "--version"),
    "samtools": ("samtools", "--version"),
    "snakemake": ("snakemake", "--version"),
}
IGNORED_COMMANDS = {
    "cat",
    "cd",
    "cp",
    "echo",
    "else",
    "export",
    "fi",
    "for",
    "if",
    "ln",
    "mkdir",
    "mv",
    "perl",
    "printf",
    "rm",
    "sed",
    "set",
    "source",
    "test",
    "then",
    "touch",
}


@dataclass(frozen=True)
class RuleSummary:
    name: str
    command: str
    tool_names: tuple[str, ...]
    tool_versions: dict[str, str]


def utc_stamp() -> str:
    return datetime.now(UTC).replace(microsecond=0).strftime("%Y%m%dT%H%M%SZ")


def _strip_shell_markup(body: str) -> str:
    text = body.strip()
    while text.startswith(("r", "f", "u", "b")) and len(text) > 1 and text[1] in {"'", '"'}:
        text = text[1:]
    return text.strip().strip(",").strip().strip("'\"")


def _first_command_line(shell_body: str) -> str:
    for line in _strip_shell_markup(shell_body).splitlines():
        cleaned = line.strip()
        if cleaned and not cleaned.startswith("#"):
            return " ".join(cleaned.split())
    return ""


def _extract_tools(command: str) -> tuple[str, ...]:
    tools: list[str] = []
    for token in COMMAND_TOKEN_RE.findall(command):
        if token in IGNORED_COMMANDS or token.startswith("{"):
            continue
        if token not in tools:
            tools.append(token)
    return tuple(tools[:8])


def _version_for_tool(tool: str) -> str:
    command = SAFE_VERSION_COMMANDS.get(tool)
    if command is None:
        return "unavailable"
    if shutil.which(command[0]) is None:
        return "unavailable"
    try:
        result = subprocess.run(
            list(command),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return "unavailable"
    first_line = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""
    return first_line or "unavailable"


def parse_rule_summaries(workflow_root: Path) -> list[RuleSummary]:
    rules_dir = workflow_root / "rules"
    if not rules_dir.is_dir():
        raise PipelineReportError(f"Rules directory is missing: {rules_dir}")
    summaries: list[RuleSummary] = []
    for path in sorted(rules_dir.glob("*.smk")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for rule_match in RULE_RE.finditer(text):
            rule_name = rule_match.group(1)
            next_rule = text.find("\nrule ", rule_match.end())
            block = text[rule_match.start() : next_rule if next_rule != -1 else len(text)]
            shell_match = SHELL_RE.search(block)
            command = _first_command_line(shell_match.group("body")) if shell_match else ""
            tools = _extract_tools(command)
            summaries.append(
                RuleSummary(
                    name=rule_name,
                    command=command or "no shell command",
                    tool_names=tools,
                    tool_versions={tool: _version_for_tool(tool) for tool in tools},
                )
            )
    if not summaries:
        raise PipelineReportError(f"No Snakemake rule summaries found under: {rules_dir}")
    return summaries


def sample_names(config_dir: Path) -> list[str]:
    samples_path = config_dir / "samples.tsv"
    if not samples_path.is_file():
        return []
    with samples_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            return []
        sample_column = "sample" if "sample" in reader.fieldnames else "Sample"
        if sample_column not in reader.fieldnames:
            sample_column = reader.fieldnames[0]
        names = [str(row.get(sample_column, "")).strip() for row in reader]
    return sorted({name for name in names if name})


def benchmark_stats(analysis_root: Path, genome_build: str) -> dict[str, dict[str, float | int]]:
    summary_path = analysis_root / "results" / "day" / genome_build / "reports" / "benchmarks_summary.tsv"
    if not summary_path.is_file():
        return {}
    stats: dict[str, list[float]] = {}
    with summary_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            return {}
        rule_field = next((field for field in reader.fieldnames if field.lower() in {"rule", "rulename"}), "")
        runtime_field = next(
            (
                field
                for field in reader.fieldnames
                if field.lower() in {"runtime", "runtime_seconds", "seconds", "s", "wall_seconds"}
            ),
            "",
        )
        if not rule_field or not runtime_field:
            return {}
        for row in reader:
            rule = str(row.get(rule_field, "")).strip()
            raw_runtime = str(row.get(runtime_field, "")).strip()
            if not rule or not raw_runtime:
                continue
            try:
                stats.setdefault(rule, []).append(float(raw_runtime))
            except ValueError:
                continue
    return {
        rule: {
            "count": len(values),
            "avg": mean(values),
            "min": min(values),
            "max": max(values),
        }
        for rule, values in sorted(stats.items())
        if values
    }


def write_pipeline_details(
    *,
    analysis_root: Path,
    workflow_root: Path,
    output_path: Path,
    genome_build: str,
    command: str,
) -> list[RuleSummary]:
    summaries = parse_rule_summaries(workflow_root)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Pipeline Details",
        "",
        f"- Generated: {datetime.now(UTC).replace(microsecond=0).isoformat().replace('+00:00', 'Z')}",
        f"- Analysis root: `{analysis_root}`",
        f"- Genome build: `{genome_build}`",
        f"- Launch command: `{command}`",
        "",
        "## Rule Tool Inventory",
        "",
        "| Rule | Command | Tools | Versions |",
        "|---|---|---|---|",
    ]
    for summary in summaries:
        versions = ", ".join(
            f"{tool}: {version}" for tool, version in sorted(summary.tool_versions.items())
        )
        lines.append(
            "| "
            + " | ".join(
                [
                    summary.name,
                    summary.command.replace("|", "\\|"),
                    ", ".join(summary.tool_names) or "none",
                    versions.replace("|", "\\|") or "none",
                ]
            )
            + " |"
        )
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summaries


def _mermaid_label(
    *,
    summary: RuleSummary,
    state: str,
    samples: list[str],
    runtime_stats: dict[str, float | int] | None,
) -> str:
    shown_samples = ", ".join(samples[:8]) if samples else "none"
    if len(samples) > 8:
        shown_samples += f", +{len(samples) - 8} more"
    if state == "planned":
        complete, running, pending, failed = 0, 0, 1, 0
    elif state == "checkpoint":
        complete, running, pending, failed = 0, 1, 0, 0
    elif state == "final_success":
        complete, running, pending, failed = 1, 0, 0, 0
    else:
        complete, running, pending, failed = 0, 0, 0, 1
    if runtime_stats:
        runtime = (
            f"avg={runtime_stats['avg']:.2f}s min={runtime_stats['min']:.2f}s "
            f"max={runtime_stats['max']:.2f}s"
        )
    else:
        runtime = "avg=n/a min=n/a max=n/a"
    command = summary.command[:120]
    versions = ", ".join(
        f"{tool} {version}" for tool, version in sorted(summary.tool_versions.items())
    )
    versions = versions[:120] if versions else "none"
    return (
        f"{summary.name}<br/>samples: {shown_samples}<br/>"
        f"complete: {complete} running: {running} pending: {pending} failed: {failed}<br/>"
        f"cmd: {command}<br/>versions: {versions}<br/>{runtime}"
    ).replace('"', "'")


def write_mermaid(
    *,
    summaries: list[RuleSummary],
    analysis_root: Path,
    genome_build: str,
    state: str,
    output_path: Path,
) -> None:
    samples = sample_names(analysis_root / "config")
    stats = benchmark_stats(analysis_root, genome_build)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "%%{init: {\"theme\":\"base\",\"themeVariables\":{\"primaryColor\":\"#12343b\",\"primaryTextColor\":\"#ffffff\",\"primaryBorderColor\":\"#1f7a8c\",\"lineColor\":\"#334155\",\"secondaryColor\":\"#f6f1d1\",\"tertiaryColor\":\"#b91c1c\",\"fontFamily\":\"Inter,Arial,sans-serif\"}}}%%",
        "flowchart TB",
        '  start["DayOA workflow snapshot"]:::start',
    ]
    previous = "start"
    for idx, summary in enumerate(summaries, start=1):
        node_id = f"r{idx}"
        label = _mermaid_label(
            summary=summary,
            state=state,
            samples=samples,
            runtime_stats=stats.get(summary.name),
        )
        lines.append(f'  {node_id}["{label}"]:::rule')
        lines.append(f"  {previous} --> {node_id}")
        previous = node_id
    lines.extend(
        [
            "  classDef start fill:#12343b,stroke:#0f766e,color:#fff,stroke-width:3px",
            "  classDef rule fill:#f8fafc,stroke:#1f7a8c,color:#111827,stroke-width:2px",
        ]
    )
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_mermaid_pdf(mmd_path: Path, pdf_path: Path, renderer: str = "mmdc") -> None:
    if shutil.which(renderer) is None:
        raise PipelineReportError(
            f"Required Mermaid renderer is missing from PATH: {renderer}"
        )
    pdf_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [renderer, "-i", str(mmd_path), "-o", str(pdf_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != 0:
        raise PipelineReportError(
            f"Mermaid PDF rendering failed for {mmd_path}: {result.stdout.strip()}"
        )


def write_snapshot(
    *,
    analysis_root: Path,
    workflow_root: Path,
    output_dir: Path,
    genome_build: str,
    state: str,
    command: str,
    renderer: str,
    write_details: bool,
) -> tuple[Path, Path, Path | None]:
    if state not in {"planned", "checkpoint", "final_success", "final_failed"}:
        raise PipelineReportError(f"Unknown workflow snapshot state: {state}")
    details_path = analysis_root / "pipeline_details.md"
    summaries = (
        write_pipeline_details(
            analysis_root=analysis_root,
            workflow_root=workflow_root,
            output_path=details_path,
            genome_build=genome_build,
            command=command,
        )
        if write_details or not details_path.is_file()
        else parse_rule_summaries(workflow_root)
    )
    suffix = state if state != "checkpoint" else f"checkpoint_{utc_stamp()}"
    mmd_path = output_dir / f"pipeline_workflow_{suffix}.mmd"
    pdf_path = output_dir / f"pipeline_workflow_{suffix}.pdf"
    write_mermaid(
        summaries=summaries,
        analysis_root=analysis_root,
        genome_build=genome_build,
        state=state,
        output_path=mmd_path,
    )
    render_mermaid_pdf(mmd_path, pdf_path, renderer=renderer)
    return mmd_path, pdf_path, details_path if write_details else None


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Write DayOA workflow reports and diagrams.")
    parser.add_argument("--analysis-root", required=True)
    parser.add_argument("--workflow-root", default="workflow")
    parser.add_argument("--output-dir", default=".")
    parser.add_argument("--genome-build", required=True)
    parser.add_argument("--state", required=True, choices=("planned", "checkpoint", "final_success", "final_failed"))
    parser.add_argument("--command", required=True)
    parser.add_argument("--renderer", default="mmdc")
    parser.add_argument("--write-details", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    try:
        write_snapshot(
            analysis_root=Path(args.analysis_root),
            workflow_root=Path(args.workflow_root),
            output_dir=Path(args.output_dir),
            genome_build=args.genome_build,
            state=args.state,
            command=args.command,
            renderer=args.renderer,
            write_details=args.write_details,
        )
    except PipelineReportError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
