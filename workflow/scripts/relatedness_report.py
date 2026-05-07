import csv
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd
from jinja2 import Template


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


def _lower_columns(frame: pd.DataFrame) -> pd.DataFrame:
    frame = frame.copy()
    frame.columns = [str(column).lower() for column in frame.columns]
    return frame


def load_manifest(path: str | os.PathLike[str]) -> pd.DataFrame:
    frame = pd.read_csv(path, sep="\t", dtype=str, keep_default_na=False, na_values=[])
    required = {"sample_id", "path", "path_type"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"Relatedness manifest missing required columns: {sorted(missing)}")
    if frame["sample_id"].duplicated().any():
        duplicated = sorted(frame.loc[frame["sample_id"].duplicated(), "sample_id"].unique())
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
    somalier_pairs: pd.DataFrame,
    manifest: pd.DataFrame,
    expected: dict[tuple[str, str], str] | None = None,
    thresholds: dict[str, float] | None = None,
) -> list[ClassifiedPair]:
    pairs = _lower_columns(somalier_pairs)
    sample_ids = set(manifest["sample_id"])
    manifest_by_sample = manifest.set_index("sample_id", drop=False)
    expected = expected or {}

    sample_a_col = "sample_a" if "sample_a" in pairs.columns else "sample1"
    sample_b_col = "sample_b" if "sample_b" in pairs.columns else "sample2"
    if sample_a_col not in pairs.columns or sample_b_col not in pairs.columns:
        raise ValueError("Somalier pairs table must contain sample_a/sample_b columns.")

    rows: list[ClassifiedPair] = []
    for row in pairs.itertuples(index=False):
        values = row._asdict()
        sample_a = str(values[sample_a_col])
        sample_b = str(values[sample_b_col])
        if sample_a not in sample_ids or sample_b not in sample_ids:
            raise ValueError(
                f"Somalier pair references sample absent from manifest: {sample_a}, {sample_b}"
            )
        relatedness = _as_float(values.get("relatedness"))
        ibs0 = _as_float(values.get("ibs0"))
        observed = classify_relationship(relatedness, ibs0, thresholds)
        exp = expected.get(tuple(sorted([sample_a, sample_b])), "")
        status, note = expected_status(observed, exp)
        rows.append(
            ClassifiedPair(
                sample_a=sample_a,
                sample_b=sample_b,
                sex_a=str(manifest_by_sample.loc[sample_a].get("sex", "")),
                sex_b=str(manifest_by_sample.loc[sample_b].get("sex", "")),
                family_id_a=str(manifest_by_sample.loc[sample_a].get("family_id", "")),
                family_id_b=str(manifest_by_sample.loc[sample_b].get("family_id", "")),
                relatedness=relatedness,
                ibs0=ibs0,
                relationship=observed,
                expected_relationship=exp,
                status=status,
                note=note,
            )
        )
    return rows


def rows_to_frame(rows: list[ClassifiedPair]) -> pd.DataFrame:
    if not rows:
        return pd.DataFrame(columns=PAIR_COLUMNS)
    return pd.DataFrame([row.__dict__ for row in rows], columns=PAIR_COLUMNS)


def write_report(
    pairs_frame: pd.DataFrame,
    manifest: pd.DataFrame,
    output_pairs: str,
    output_summary: str,
    output_html: str,
) -> None:
    Path(output_pairs).parent.mkdir(parents=True, exist_ok=True)
    pairs_frame.to_csv(output_pairs, sep="\t", index=False)

    if pairs_frame.empty:
        summary = pd.DataFrame(
            [{"relationship": "no_pairs", "status": "NA", "pair_count": 0}]
        )
    else:
        summary = (
            pairs_frame.groupby(["relationship", "status"], dropna=False)
            .size()
            .reset_index(name="pair_count")
            .sort_values(["relationship", "status"])
        )
    summary.to_csv(output_summary, sep="\t", index=False)

    template = Template(
        """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Relatedness QC</title>
  <style>
    body{font-family:system-ui,Arial,sans-serif;margin:24px}
    table{border-collapse:collapse}
    td,th{border:1px solid #ccc;padding:6px 8px}
    .FAIL{background:#ffe3e3}
    .PASS{background:#e6ffed}
    .NA{background:#f7f7f7}
  </style>
</head>
<body>
  <h1>Relatedness QC</h1>
  <p><b>Samples:</b> {{ sample_count }} | <b>Pairs:</b> {{ pair_count }}</p>
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
    {% for row in rows %}
      <tr class="{{ row.status }}">
        <td>{{ row.status }}</td>
        <td>{{ row.sample_a }}</td>
        <td>{{ row.sample_b }}</td>
        <td>{{ row.relationship }}</td>
        <td>{{ row.sex_a }}</td>
        <td>{{ row.sex_b }}</td>
        <td>{{ row.family_id_a }}</td>
        <td>{{ row.family_id_b }}</td>
        <td>{{ row.expected_relationship }}</td>
        <td>{{ "%.4f"|format(row.relatedness) if row.relatedness is not none else "" }}</td>
        <td>{{ "%.4f"|format(row.ibs0) if row.ibs0 is not none else "" }}</td>
        <td>{{ row.note }}</td>
      </tr>
    {% endfor %}
    </tbody>
  </table>
</body>
</html>
"""
    )
    html = template.render(
        sample_count=len(manifest),
        pair_count=len(pairs_frame),
        rows=pairs_frame.to_dict(orient="records"),
    )
    with open(output_html, "w", encoding="utf-8") as handle:
        handle.write(html)


def run_from_snakemake(smk: Any) -> None:
    manifest = load_manifest(smk.input.manifest)
    pairs = pd.read_csv(smk.input.pairs, sep="\t", dtype=str, keep_default_na=False)
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
