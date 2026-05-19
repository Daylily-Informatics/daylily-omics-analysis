from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_ROOT = REPO_ROOT / "workflow"
SNAKEFILE = WORKFLOW_ROOT / "Snakefile"

INCLUDE_RE = re.compile(r'^\s*include:\s*[rRuUbBfF]*["\']([^"\']+)["\']')
RESERVED_ASSIGNMENT_RE = re.compile(r"^\s*(module)\s*=", re.MULTILINE)


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
