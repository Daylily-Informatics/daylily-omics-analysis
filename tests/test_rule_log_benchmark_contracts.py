from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[1]
SNAKEFILE = REPO_ROOT / "workflow" / "Snakefile"

INCLUDE_RE = re.compile(r'^\s*include:\s*"([^"]+)"')
RULE_RE = re.compile(r"^(rule|checkpoint)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:")
DIRECTIVE_RE = re.compile(r"^    ([A-Za-z_][A-Za-z0-9_]*)\s*:")
WILDCARD_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
ASSIGNMENT_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=")
FSTRING_PREFIX_RE = re.compile(r"(?P<prefix>\bf[ruRU]*|\b[ruRU]*f)(?P<quote>[\"'])", re.ASCII)
LOCALRULES_RE = re.compile(r"^\s*localrules:\s*(.*)$")

EXCLUDED_WILDCARD_NAMES = {
    "config",
    "input",
    "log",
    "output",
    "params",
    "resources",
    "threads",
    "wildcards",
}


def _resolve_include(parent: Path, target: str) -> Path:
    candidate = (parent.parent / target).resolve()
    if candidate.exists():
        return candidate
    return (SNAKEFILE.parent / target).resolve()


def _collect_imported_files(path: Path, seen: set[Path] | None = None) -> list[Path]:
    seen = seen or set()
    path = path.resolve()
    if path in seen:
        return []
    seen.add(path)

    files = [path]
    for line in path.read_text().splitlines():
        match = INCLUDE_RE.match(line)
        if match:
            files.extend(_collect_imported_files(_resolve_include(path, match.group(1)), seen))
    return files


def _localrule_names_from_text(text: str) -> set[str]:
    lines = text.splitlines()
    names = set()
    index = 0
    while index < len(lines):
        match = LOCALRULES_RE.match(lines[index])
        if not match:
            index += 1
            continue

        tail = match.group(1).strip()
        if tail:
            names.update(_parse_localrule_names(tail))
            index += 1
            continue

        index += 1
        while index < len(lines) and (
            not lines[index].strip()
            or lines[index].startswith(" ")
            or lines[index].startswith("\t")
        ):
            names.update(_parse_localrule_names(lines[index]))
            index += 1

    return names


def _parse_localrule_names(line: str) -> set[str]:
    names = set()
    for token in line.split("#", 1)[0].split(","):
        token = token.strip()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token):
            names.add(token)
    return names


def _localrules() -> set[str]:
    names = set()
    for path in _collect_imported_files(SNAKEFILE):
        names.update(_localrule_names_from_text(path.read_text()))
    return names


def _rule_starts(lines: list[str]) -> list[tuple[int, str]]:
    starts = []
    for index, line in enumerate(lines):
        match = RULE_RE.match(line)
        if match:
            starts.append((index, match.group(2)))
    return starts


def _directive_spans(
    lines: list[str], rule_start: int, rule_end: int
) -> list[tuple[int, int, str]]:
    starts = []
    for index in range(rule_start + 1, rule_end):
        match = DIRECTIVE_RE.match(lines[index])
        if match:
            starts.append((index, match.group(1)))

    spans = []
    for index, (line_index, name) in enumerate(starts):
        next_index = starts[index + 1][0] if index + 1 < len(starts) else rule_end
        spans.append((line_index, next_index, name))
    return spans


def _strip_fstring_interpolations(text: str) -> str:
    """Keep escaped Snakemake wildcards in f-strings, drop Python-only fields."""
    parts = []
    index = 0
    while index < len(text):
        match = FSTRING_PREFIX_RE.search(text, index)
        if not match:
            parts.append(text[index:])
            break

        quote = match.group("quote")
        parts.append(text[index : match.end()])
        cursor = match.end()
        literal_parts = []
        while cursor < len(text):
            char = text[cursor]
            if char == quote:
                literal_parts.append(char)
                cursor += 1
                break
            if char == "{":
                if cursor + 1 < len(text) and text[cursor + 1] == "{":
                    end = text.find("}}", cursor + 2)
                    if end != -1:
                        literal_parts.append("{" + text[cursor + 2 : end] + "}")
                        cursor = end + 2
                        continue
                end = text.find("}", cursor + 1)
                if end != -1:
                    cursor = end + 1
                    continue
            literal_parts.append(char)
            cursor += 1
        parts.append("".join(literal_parts))
        index = cursor

    return "".join(parts)


def _wildcards(lines: list[str]) -> set[str]:
    text = _strip_fstring_interpolations("\n".join(lines))
    expand_resolved_names = set(ASSIGNMENT_RE.findall(text))
    text = text.replace("{{", "{").replace("}}", "}")
    names = set()
    for match in WILDCARD_RE.finditer(text):
        name = match.group(1)
        if (
            name in EXCLUDED_WILDCARD_NAMES
            or name in expand_resolved_names
            or name.isupper()
        ):
            continue
        names.add(name)
    return names


def _rules():
    for path in _collect_imported_files(SNAKEFILE):
        relpath = path.relative_to(REPO_ROOT)
        lines = path.read_text().splitlines()
        starts = _rule_starts(lines)
        for index, (rule_start, rule_name) in enumerate(starts):
            rule_end = starts[index + 1][0] if index + 1 < len(starts) else len(lines)
            spans = _directive_spans(lines, rule_start, rule_end)
            directives = {name: (start, end) for start, end, name in spans}
            yield relpath, rule_start + 1, rule_name, lines, directives


def test_all_imported_rules_define_required_log_and_benchmark_directives():
    missing = []
    for relpath, line, rule_name, _lines, directives in _rules():
        if "log" not in directives:
            missing.append(f"{relpath}:{line}:{rule_name}:log")
        if "run" not in directives and "benchmark" not in directives:
            missing.append(f"{relpath}:{line}:{rule_name}:benchmark")

    assert missing == []


def test_run_rules_do_not_define_benchmark():
    offenders = []
    for relpath, line, rule_name, _lines, directives in _rules():
        if "run" in directives and "benchmark" in directives:
            offenders.append(f"{relpath}:{line}:{rule_name}")

    assert offenders == []


def test_shell_rules_define_benchmark():
    missing = []
    for relpath, line, rule_name, _lines, directives in _rules():
        if "shell" in directives and "benchmark" not in directives:
            missing.append(f"{relpath}:{line}:{rule_name}")

    assert missing == []


def test_nonlocal_rules_define_cluster_sample_param():
    localrules = _localrules()
    missing = []
    for relpath, line, rule_name, lines, directives in _rules():
        if rule_name in localrules:
            continue
        if "params" not in directives:
            missing.append(f"{relpath}:{line}:{rule_name}:params")
            continue
        start, end = directives["params"]
        params_block = "\n".join(lines[start:end])
        if "cluster_sample" not in params_block:
            missing.append(f"{relpath}:{line}:{rule_name}:cluster_sample")

    assert missing == []


def test_output_log_and_benchmark_wildcards_match():
    mismatches = []
    for relpath, line, rule_name, lines, directives in _rules():
        wildcard_sets = {}
        for directive_name in ("output", "log", "benchmark"):
            if directive_name not in directives:
                continue
            start, end = directives[directive_name]
            wildcard_sets[directive_name] = _wildcards(lines[start:end])

        if len({tuple(sorted(value)) for value in wildcard_sets.values()}) > 1:
            mismatches.append(
                f"{relpath}:{line}:{rule_name}:"
                + ":".join(
                    f"{name}={sorted(wildcards)}"
                    for name, wildcards in wildcard_sets.items()
                )
            )

    assert mismatches == []
