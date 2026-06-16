from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load(_read(path))


def test_mosdepth_env_pins_expected_version() -> None:
    env = _yaml("workflow/envs/mosdepth_v0.1.yaml")

    assert "mosdepth=0.3.14" in env["dependencies"]
    assert "mosdepth=0.3.2" not in env["dependencies"]


def test_mosdepth_rule_uses_strict_shell_and_checks_native_outputs() -> None:
    text = _read("workflow/rules/mosdepth.smk")
    rule = text[text.index("rule mosdepth:") : text.index("localrules:")]

    assert "set -euo pipefail" in rule
    assert "rmlogFailedMosDepth" not in rule
    assert "rm perbase failed" not in rule
    for output_name in ("summary", "global_dist", "region_dist"):
        assert f"test -s {{output.{output_name}:q}}" in rule
        assert f"{{output.{output_name}:q}}" in rule


def test_produce_mosdepth_uses_configured_alignment_qc_scope() -> None:
    text = _read("workflow/rules/mosdepth.smk")
    target = text[text.index("rule produce_mosdepth:") :]

    assert "done=MDIR + \"logs/produce_mosdepth.done\"" in target
    assert "touch {log}; touch {output.done}" in target
    assert "alnr=QC_CRAM_ALIGNERS" in target
    assert "ddup=qc_alignment_dedupers()" in target
    assert "alnr=CRAM_ALIGNERS" not in target
    assert "ddup=DDUP" not in target
    for suffix in (
        ".mosdepth.summary.txt",
        ".mosdepth.global.dist.txt",
        ".mosdepth.region.dist.txt",
    ):
        assert suffix in target
