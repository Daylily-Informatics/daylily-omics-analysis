from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_openai_token_helper_copies_to_ubuntu_path_and_exports_env(tmp_path: Path) -> None:
    token_source = tmp_path / "source" / ".config" / "openai" / "tok.tok"
    token_target = tmp_path / "ubuntu" / ".config" / "openai" / "tok.tok"
    token_source.parent.mkdir(parents=True)
    token_source.write_text("sk-test-fake-token\n", encoding="utf-8")

    command = (
        "set -euo pipefail; "
        f"export DAYOA_OPENAI_TOKEN_SOURCE={str(token_source)!r}; "
        f"export DAYOA_OPENAI_TOKEN_TARGET={str(token_target)!r}; "
        "export DAYOA_OPENAI_MODEL=gpt-5.5; "
        f"source {str(REPO_ROOT / 'bin/day_openai_env.bash')!r}; "
        "test \"$OPENAI_API_KEY\" = sk-test-fake-token; "
        "test \"$MULTIQC_AI_SUMMARY\" = 1; "
        "test \"$MULTIQC_AI_PROVIDER\" = openai; "
        "test \"$MULTIQC_AI_MODEL\" = gpt-5.5; "
        "test \"$APPTAINERENV_OPENAI_API_KEY\" = sk-test-fake-token; "
        "test \"$SINGULARITYENV_OPENAI_API_KEY\" = sk-test-fake-token; "
        f"test -f {str(token_target)!r}; "
        f"test \"$(cat {str(token_target)!r})\" = sk-test-fake-token"
    )

    result = subprocess.run(["bash", "-lc", command], text=True, capture_output=True)

    assert result.returncode == 0, result.stderr


def test_openai_token_helper_fails_hard_when_enabled_without_token(tmp_path: Path) -> None:
    missing_source = tmp_path / "missing" / "tok.tok"
    token_target = tmp_path / "ubuntu" / ".config" / "openai" / "tok.tok"
    command = (
        "set -euo pipefail; "
        f"export DAYOA_OPENAI_TOKEN_SOURCE={str(missing_source)!r}; "
        f"export DAYOA_OPENAI_TOKEN_TARGET={str(token_target)!r}; "
        f"source {str(REPO_ROOT / 'bin/day_openai_env.bash')!r}"
    )

    result = subprocess.run(["bash", "-lc", command], text=True, capture_output=True)

    assert result.returncode == 2
    assert "OpenAI token file not found" in result.stderr
    assert "sk-" not in result.stderr


def test_gather_rules_do_not_use_sigpipe_prone_find_head_pipelines() -> None:
    bad_find_to_head = re.compile(r"find\b[^\n;]*\|[^\n;]*\bhead\b")

    for path in (
        "workflow/rules/seqfu.smk",
        "workflow/rules/calc_coverage_eveness.smk",
        "workflow/rules/calc_coverage_evenness_two.smk",
        "bin/util/benchmarks/collect_day_benchmark_data.sh",
    ):
        assert not bad_find_to_head.search(_read(path)), path


def test_benchmark_collector_avoids_full_results_tree_scan() -> None:
    collector = _read("bin/util/benchmarks/collect_day_benchmark_data.sh")

    assert "fd -p -L" not in collector
    assert "parallel -j" not in collector
    assert "ls -1" not in collector
    assert "head -n 1 \"${bench_files[0]}\"" in collector
    assert 'find "$bench_dir" -maxdepth 1 -type f -name "*.bench.tsv" -print0' in collector


def test_coverage_gathers_are_declared_input_driven() -> None:
    coverage_one = _read("workflow/rules/calc_coverage_eveness.smk")
    coverage_two = _read("workflow/rules/calc_coverage_evenness_two.smk")

    assert "mqc=expand(" in coverage_one
    assert "coverage_files=({input.mqc:q});" in coverage_one
    assert "find results" not in coverage_one
    assert "parallel -j" not in coverage_one

    assert "metrics=expand(" in coverage_two
    assert "metrics_files=({input.metrics:q});" in coverage_two
    assert "find results" not in coverage_two
    assert "parallel -j" not in coverage_two


def test_report_gather_shell_arrays_escape_snakemake_braces() -> None:
    seqfu = _read("workflow/rules/seqfu.smk")
    coverage_one = _read("workflow/rules/calc_coverage_eveness.smk")
    coverage_two = _read("workflow/rules/calc_coverage_evenness_two.smk")

    for expected in (
        "${{#r1_files[@]}}",
        "${{r1_files[0]}}",
        "${{r1_files[@]}}",
        "${{#r2_files[@]}}",
        "${{r2_files[0]}}",
        "${{r2_files[@]}}",
    ):
        assert expected in seqfu

    for expected in (
        "${{#coverage_files[@]}}",
        "${{coverage_files[0]}}",
        "${{coverage_files[@]}}",
    ):
        assert expected in coverage_one

    for expected in (
        "${{#metrics_files[@]}}",
        "${{metrics_files[0]}}",
        "${{metrics_files[@]}}",
    ):
        assert expected in coverage_two


def test_day_run_preserves_nonzero_workflow_exit_after_failure_marker() -> None:
    day_run = _read("bin/day_run")
    non_dry_run_block = day_run.split('if [[ "$_is_dry_run" == "true" ]]; then', 1)[1]
    failure_marker_index = non_dry_run_block.index("daylily.failed_run")
    ret_capture_index = non_dry_run_block.index("ret_code=$?")

    assert ret_capture_index < failure_marker_index
    assert 'if [[ "$ret_code" -ne 0 ]]; then' in non_dry_run_block
    assert ") || echo" not in non_dry_run_block
    assert "exit $ret_code" in day_run


def test_day_run_failed_snakemake_writes_marker_and_exits_nonzero(tmp_path: Path) -> None:
    fakebin = tmp_path / "fakebin"
    profile = tmp_path / "profile"
    fake_tmp = tmp_path / "daytmp"
    fakebin.mkdir()
    profile.mkdir()
    (tmp_path / "bin").symlink_to(REPO_ROOT / "bin", target_is_directory=True)

    (fakebin / "yq").write_text(
        '#!/usr/bin/env bash\nprintf "%s\\n" "$DAY_TEST_TMPDIR"\n',
        encoding="utf-8",
    )
    (fakebin / "snakemake").write_text(
        """#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == "--unlock" ]]; then
        exit 0
    fi
done
exit 17
""",
        encoding="utf-8",
    )
    (fakebin / "yq").chmod(0o755)
    (fakebin / "snakemake").chmod(0o755)

    (profile / "profile_env.bash").write_text(
        """colr() { printf '%s\\n' "$1" >&2; }
DY_WT0=
DY_WB0=
DY_WS1=
DY_IT0=
DY_IB0=
DY_IS1=
DY_IB0=
DY_IS0=
""",
        encoding="utf-8",
    )
    (profile / "rule_config.yaml").write_text("{}\n", encoding="utf-8")
    (profile / "config.yaml").write_text("{}\n", encoding="utf-8")

    env = {
        **os.environ,
        "PATH": f"{fakebin}:{os.environ['PATH']}",
        "DAY_ROOT": str(tmp_path),
        "DAY_PROFILE": "test",
        "DAY_PROFILE_DIR": str(profile),
        "DAY_GENOME_BUILD": "hg38",
        "DAY_TEST_TMPDIR": str(fake_tmp),
    }

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "bin/day_run"), "produce_failure"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 17
    assert (tmp_path / "daylily.failed_run").read_text(encoding="utf-8").strip()
    assert not (tmp_path / "daylily.successful_run").exists()


def test_dyoainit_budget_and_optional_variable_contracts() -> None:
    dyoainit = _read("dyoainit")

    assert 'if [[ "$SKIP_PROJECT_CHECK" == true ]]; then' in dyoainit
    assert 'export TOTAL_BUDGET="NA"' in dyoainit
    assert 'export USED_BUDGET="NA"' in dyoainit
    assert 'export PERCENT_USED="NA"' in dyoainit
    assert 'export AWS_ACCOUNT_ID="NA"' in dyoainit
    assert "bc -l" not in dyoainit
    assert "DEFAULTING TO PROJECT=daylily-global" not in dyoainit

    assert "cluster_config_tag_value()" in dyoainit
    assert "aws-parallelcluster-enforce-budget" in dyoainit
    assert "Notice: Cluster config sets aws-parallelcluster-enforce-budget=skip" in dyoainit
    assert dyoainit.index('if [[ "$SKIP_PROJECT_CHECK" == true ]]; then') < dyoainit.index(
        "aws sts get-caller-identity"
    )

    assert "day_current_user()" in dyoainit
    assert "id -un" in dyoainit
    assert 'DAY_USER="$(day_current_user)"' in dyoainit
    assert 'export USER="${USER:-$DAY_USER}"' in dyoainit
    assert "${BASH_SOURCE[0]:-}" in dyoainit
    assert "${2:-}" in dyoainit
    assert "${USER:-}" in dyoainit
    assert "${PS1:-}" in dyoainit
    assert "${SHELL:-}" in dyoainit
    assert "${1:-}" in dyoainit


def test_shell_wrappers_have_valid_bash_syntax() -> None:
    for path in ("bin/day_run", "dyoainit"):
        subprocess.run(["bash", "-n", path], cwd=REPO_ROOT, check=True)
