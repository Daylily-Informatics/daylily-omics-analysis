import csv
import html
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping


DEFAULT_THRESHOLDS = {
    "duplicate_min_relatedness": 0.95,
    "first_degree_min_relatedness": 0.40,
    "parent_child_max_ibs0": 2.0,
    "unrelated_max_relatedness": 0.20,
}

PAIR_COLUMNS = [
    "sample_a",
    "sample_b",
    "sex_a",
    "sex_b",
    "family_id_a",
    "family_id_b",
    "relatedness",
    "ibs0",
    "relationship",
    "expected_relationship",
    "status",
    "note",
]


class SimpleTable(list[dict[str, str]]):
    """Small column-addressable table for Snakemake script execution."""

    @property
    def columns(self) -> list[str]:
        if not self:
            return []
        return list(self[0].keys())

    def __getitem__(self, key: Any) -> Any:
        if isinstance(key, str):
            return [row.get(key, "") for row in self]
        return super().__getitem__(key)


@dataclass(frozen=True)
class ClassifiedPair:
    sample_a: str
    sample_b: str
    sex_a: str
    sex_b: str
    family_id_a: str
    family_id_b: str
    relatedness: float | None
    ibs0: float | None
    relationship: str
    expected_relationship: str
    status: str
    note: str


def _as_float(value: Any) -> float | None:
    if value in ["", None, "None", "nan"]:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _thresholds(overrides: dict[str, Any] | None = None) -> dict[str, float]:
    merged = dict(DEFAULT_THRESHOLDS)
    for key, value in (overrides or {}).items():
        if key not in merged:
            raise ValueError(f"Unknown relationship threshold: {key}")
        merged[key] = float(value)
    return merged


def classify_relationship(
    relatedness: float | None,
    ibs0: float | None,
    thresholds: dict[str, float] | None = None,
) -> str:
    thresh = _thresholds(thresholds)
    if relatedness is None:
        return "ambiguous"
    if relatedness >= thresh["duplicate_min_relatedness"]:
        return "duplicate_or_identical"
    if relatedness >= thresh["first_degree_min_relatedness"]:
        if ibs0 is not None and ibs0 <= thresh["parent_child_max_ibs0"]:
            return "parent_child"
        return "sibling_or_first_degree"
    if relatedness <= thresh["unrelated_max_relatedness"]:
        return "unrelated"
    return "ambiguous"


def _records(table: Any) -> list[dict[str, Any]]:
    if hasattr(table, "to_dict"):
        return list(table.to_dict(orient="records"))
    return [dict(row) for row in table]


def _lower_records(table: Any) -> list[dict[str, Any]]:
    return [
        {str(key).strip().lower().lstrip("#"): value for key, value in row.items()}
        for row in _records(table)
    ]


def load_manifest(path: str | os.PathLike[str]) -> SimpleTable:
    with open(path, newline="", encoding="utf-8") as handle:
        frame = SimpleTable(
            {key: value for key, value in row.items()}
            for row in csv.DictReader(handle, delimiter="\t")
        )
    required = {"sample_id", "path", "path_type"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"Relatedness manifest missing required columns: {sorted(missing)}")
    sample_ids = frame["sample_id"]
    duplicated = sorted({sample for sample in sample_ids if sample_ids.count(sample) > 1})
    if duplicated:
        raise ValueError(f"Duplicate sample_id values in relatedness manifest: {duplicated}")
    return frame


def load_expected(expected: Any) -> dict[tuple[str, str], str]:
    if expected in ["", None, "None"]:
        return {}
    if isinstance(expected, list):
        entries = expected
    else:
        expected_path = Path(str(expected))
        if not expected_path.exists():
            raise ValueError(f"Expected relationship file not found: {expected_path}")
        with expected_path.open(newline="", encoding="utf-8") as handle:
            entries = list(csv.DictReader(handle, delimiter="\t"))

    result: dict[tuple[str, str], str] = {}
    for entry in entries:
        relationship = str(entry.get("relationship", "")).strip()
        samples = entry.get("samples")
        if isinstance(samples, str):
            sample_a, sample_b = [item.strip() for item in samples.split(",", 1)]
        else:
            sample_a, sample_b = samples
        if not relationship or not sample_a or not sample_b:
            raise ValueError(f"Invalid expected relationship entry: {entry}")
        result[tuple(sorted([sample_a, sample_b]))] = relationship
    return result


def expected_status(observed: str, expected: str) -> tuple[str, str]:
    if not expected:
        return "NA", ""
    normalized = {
        "identical": "duplicate_or_identical",
        "duplicate": "duplicate_or_identical",
        "parent-offspring": "parent_child",
        "parent_child": "parent_child",
        "mother_child": "parent_child",
        "father_child": "parent_child",
        "siblings": "sibling_or_first_degree",
        "sibling": "sibling_or_first_degree",
        "first_degree": "sibling_or_first_degree",
        "unrelated": "unrelated",
    }.get(expected, expected)
    if observed == normalized:
        return "PASS", ""
    return "FAIL", f"expected {expected}; observed {observed}"


def classify_pairs(
    somalier_pairs: Any,
    manifest: SimpleTable,
    expected: dict[tuple[str, str], str] | None = None,
    thresholds: dict[str, float] | None = None,
) -> list[ClassifiedPair]:
    pairs = _lower_records(somalier_pairs)
    manifest_by_sample: dict[str, dict[str, str]] = {}
    for manifest_row in manifest:
        manifest_by_sample[manifest_row["sample_id"]] = manifest_row
        external_sample_id = manifest_row.get("external_sample_id", "")
        if external_sample_id:
            manifest_by_sample[external_sample_id] = manifest_row
    expected = expected or {}
    if not pairs:
        return []

    pair_columns = set(pairs[0].keys()) if pairs else set()
    sample_a_col = "sample_a" if "sample_a" in pair_columns else "sample1"
    sample_b_col = "sample_b" if "sample_b" in pair_columns else "sample2"
    if sample_a_col not in pair_columns or sample_b_col not in pair_columns:
        raise ValueError("Somalier pairs table must contain sample_a/sample_b columns.")

    rows: list[ClassifiedPair] = []
    for values in pairs:
        raw_sample_a = str(values[sample_a_col])
        raw_sample_b = str(values[sample_b_col])
        if raw_sample_a not in manifest_by_sample or raw_sample_b not in manifest_by_sample:
            raise ValueError(
                "Somalier pair references sample absent from manifest: "
                f"{raw_sample_a}, {raw_sample_b}"
            )
        sample_a_row = manifest_by_sample[raw_sample_a]
        sample_b_row = manifest_by_sample[raw_sample_b]
        sample_a = str(sample_a_row["sample_id"])
        sample_b = str(sample_b_row["sample_id"])
        relatedness = _as_float(values.get("relatedness"))
        ibs0 = _as_float(values.get("ibs0"))
        observed = classify_relationship(relatedness, ibs0, thresholds)
        exp = expected.get(tuple(sorted([sample_a, sample_b])), "") or expected.get(
            tuple(sorted([raw_sample_a, raw_sample_b])), ""
        )
        status, note = expected_status(observed, exp)
        rows.append(
            ClassifiedPair(
                sample_a=sample_a,
                sample_b=sample_b,
                sex_a=str(sample_a_row.get("sex", "")),
                sex_b=str(sample_b_row.get("sex", "")),
                family_id_a=str(sample_a_row.get("family_id", "")),
                family_id_b=str(sample_b_row.get("family_id", "")),
                relatedness=relatedness,
                ibs0=ibs0,
                relationship=observed,
                expected_relationship=exp,
                status=status,
                note=note,
            )
        )
    return rows


def rows_to_frame(rows: list[ClassifiedPair]) -> list[dict[str, Any]]:
    if not rows:
        return []
    return [{column: row.__dict__.get(column, "") for column in PAIR_COLUMNS} for row in rows]


def write_report(
    pairs_frame: Iterable[Mapping[str, Any]],
    manifest: SimpleTable,
    output_pairs: str,
    output_summary: str,
    output_html: str,
) -> None:
    Path(output_pairs).parent.mkdir(parents=True, exist_ok=True)
    pairs_rows = [dict(row) for row in pairs_frame]
    with open(output_pairs, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=PAIR_COLUMNS, delimiter="\t")
        writer.writeheader()
        writer.writerows(pairs_rows)

    if not pairs_rows:
        summary_rows = [{"relationship": "no_pairs", "status": "NA", "pair_count": 0}]
    else:
        counts: dict[tuple[str, str], int] = {}
        for row in pairs_rows:
            key = (str(row.get("relationship", "")), str(row.get("status", "")))
            counts[key] = counts.get(key, 0) + 1
        summary_rows = [
            {"relationship": relationship, "status": status, "pair_count": count}
            for (relationship, status), count in sorted(counts.items())
        ]
    with open(output_summary, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["relationship", "status", "pair_count"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    body_rows = "\n".join(
        "      <tr class=\"{status}\">"
        "<td>{status}</td><td>{sample_a}</td><td>{sample_b}</td>"
        "<td>{relationship}</td><td>{sex_a}</td><td>{sex_b}</td>"
        "<td>{family_id_a}</td><td>{family_id_b}</td>"
        "<td>{expected_relationship}</td><td>{relatedness}</td>"
        "<td>{ibs0}</td><td>{note}</td></tr>".format(
            **{
                key: html.escape("" if value is None else str(value))
                for key, value in row.items()
            }
        )
        for row in pairs_rows
    )
    report_html = f"""
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Relatedness QC</title>
  <style>
    body{{font-family:system-ui,Arial,sans-serif;margin:24px}}
    table{{border-collapse:collapse}}
    td,th{{border:1px solid #ccc;padding:6px 8px}}
    .FAIL{{background:#ffe3e3}}
    .PASS{{background:#e6ffed}}
    .NA{{background:#f7f7f7}}
  </style>
</head>
<body>
  <h1>Relatedness QC</h1>
  <p><b>Samples:</b> {len(manifest)} | <b>Pairs:</b> {len(pairs_rows)}</p>
  <h2>Pair Classifications</h2>
  <table>
    <thead>
      <tr>
        <th>Status</th><th>Sample A</th><th>Sample B</th><th>Relationship</th>
        <th>Sex A</th><th>Sex B</th><th>Family A</th><th>Family B</th>
        <th>Expected</th><th>Relatedness</th><th>IBS0</th><th>Note</th>
      </tr>
    </thead>
    <tbody>
{body_rows}
    </tbody>
  </table>
</body>
</html>
""".lstrip()
    with open(output_html, "w", encoding="utf-8") as handle:
        handle.write(report_html)


def run_from_snakemake(smk: Any) -> None:
    manifest = load_manifest(smk.input.manifest)
    with open(smk.input.pairs, newline="", encoding="utf-8") as handle:
        pairs = list(csv.DictReader(handle, delimiter="\t"))
    expected = load_expected(smk.params.expected)
    thresholds = _thresholds(dict(smk.params.thresholds or {}))
    classified = classify_pairs(pairs, manifest, expected=expected, thresholds=thresholds)
    write_report(
        rows_to_frame(classified),
        manifest,
        smk.output.pairs_classified,
        smk.output.summary,
        smk.output.html,
    )


if "snakemake" in globals():
    run_from_snakemake(globals()["snakemake"])
