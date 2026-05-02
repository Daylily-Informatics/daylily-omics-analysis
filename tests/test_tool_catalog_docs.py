from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = REPO_ROOT / "docs" / "catalog_of_tools.md"
README_PATH = REPO_ROOT / "README.md"

REQUIRED_COLUMNS = [
    "Tool / integration",
    "Stage",
    "Daylily target(s) / rule(s)",
    "Input file producers",
    "Output file types",
    "Brief output description",
    "Code evidence",
    "Env / version evidence",
    "Upstream link",
    "Packaged or referenced test data",
    "Pytest coverage",
    "Documented test invocation",
    "No tests?",
    "Published validation paper / whitepaper",
    "Documented clinical use?",
    "Notes",
]

REQUIRED_STAGES = {
    "Input/Demux",
    "FASTQ QC/Prep",
    "Alignment",
    "Dedup",
    "SNV/Small Variant",
    "SV/CNV/STR/HTD",
    "Contamination/Relatedness",
    "QC/Metrics/Reporting",
    "Concordance/Benchmarking",
    "Internal/Daylily Utilities",
}


def _split_table_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _catalog_rows() -> list[dict[str, str]]:
    lines = CATALOG_PATH.read_text(encoding="utf-8").splitlines()
    header_index = next(
        i for i, line in enumerate(lines) if line.startswith("| Tool / integration |")
    )
    headers = _split_table_row(lines[header_index])
    rows: list[dict[str, str]] = []
    for line in lines[header_index + 2 :]:
        if not line.startswith("|"):
            break
        cells = _split_table_row(line)
        assert len(cells) == len(headers), line
        rows.append(dict(zip(headers, cells, strict=True)))
    return rows


def test_readme_links_tool_catalog() -> None:
    readme = README_PATH.read_text(encoding="utf-8")

    assert "[`docs/catalog_of_tools.md`](docs/catalog_of_tools.md)" in readme


def test_tool_catalog_exists_and_declares_evidence_policy() -> None:
    text = CATALOG_PATH.read_text(encoding="utf-8")

    assert "# Catalog Of Tools" in text
    assert "A row is included only when the tool is present" in text
    assert "Web lookup is used only to enrich" in text


def test_tool_catalog_table_schema_and_rows() -> None:
    rows = _catalog_rows()

    assert len(rows) >= 40
    assert list(rows[0]) == REQUIRED_COLUMNS
    assert REQUIRED_STAGES <= {row["Stage"] for row in rows}

    for row in rows:
        assert row["Tool / integration"], row
        assert row["Stage"], row
        assert row["Code evidence"], row
        assert row["No tests?"] in {"yes", "no"}, row
