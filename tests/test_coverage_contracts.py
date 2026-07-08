from __future__ import annotations

import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_python_coverage_boundary_is_explicit_and_thresholded() -> None:
    pyproject = tomllib.loads((REPO_ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    coverage_run = pyproject["tool"]["coverage"]["run"]
    coverage_report = pyproject["tool"]["coverage"]["report"]

    assert coverage_run["source"] == ["daylily_omics_analysis"]
    assert coverage_report["fail_under"] >= 80
    assert coverage_report["show_missing"] is True


def test_workflow_surface_has_noncoverage_contract_gates_documented() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    tests_readme = (REPO_ROOT / "tests" / "README.md").read_text(encoding="utf-8")

    required_gates = [
        "bash tests/test_cli_commands.sh",
        "bash tests/test_bclconvert_bootstrap.sh",
        "python -m coverage run -m pytest -q tests",
        "tests/test_rule_log_benchmark_contracts.py",
        "tests/test_snakemake_parser_contracts.py",
        "tests/test_shell_wrapper_contracts.py",
    ]

    combined = readme + "\n" + tests_readme
    missing = [gate for gate in required_gates if gate not in combined]
    assert missing == []


def test_active_workflow_surface_is_larger_than_package_coverage() -> None:
    package_modules = list((REPO_ROOT / "daylily_omics_analysis").rglob("*.py"))
    workflow_rules = list((REPO_ROOT / "workflow" / "rules").glob("*.smk"))
    workflow_scripts = list((REPO_ROOT / "workflow" / "scripts").glob("*.py"))

    assert len(package_modules) == 7
    assert len(workflow_rules) > len(package_modules) * 10
    assert len(workflow_scripts) > len(package_modules) * 5

