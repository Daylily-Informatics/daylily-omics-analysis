from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_openai_token_helper_copies_to_ubuntu_path_and_exports_env(
    tmp_path: Path,
) -> None:
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
        'test "$OPENAI_API_KEY" = sk-test-fake-token; '
        'test "$MULTIQC_AI_SUMMARY" = 1; '
        'test "$MULTIQC_AI_PROVIDER" = openai; '
        'test "$MULTIQC_AI_MODEL" = gpt-5.5; '
        'test "$APPTAINERENV_OPENAI_API_KEY" = sk-test-fake-token; '
        'test "$SINGULARITYENV_OPENAI_API_KEY" = sk-test-fake-token; '
        f"test -f {str(token_target)!r}; "
        f'test "$(cat {str(token_target)!r})" = sk-test-fake-token'
    )

    result = subprocess.run(["bash", "-lc", command], text=True, capture_output=True)

    assert result.returncode == 0, result.stderr


def test_openai_token_helper_fails_hard_when_enabled_without_token(
    tmp_path: Path,
) -> None:
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
    assert 'head -n 1 "${bench_files[0]}"' in collector
    assert (
        'find "$bench_dir" -maxdepth 1 -type f -name "*.bench.tsv" -print0' in collector
    )


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


def test_day_run_failed_snakemake_writes_marker_and_exits_nonzero(
    tmp_path: Path,
) -> None:
    fakebin = tmp_path / "fakebin"
    profile = tmp_path / "profile"
    fake_tmp = tmp_path / "daytmp"
    fakebin.mkdir()
    profile.mkdir()
    (tmp_path / "bin").symlink_to(REPO_ROOT / "bin", target_is_directory=True)
    (tmp_path / "workflow").symlink_to(REPO_ROOT / "workflow", target_is_directory=True)

    (fakebin / "yq").write_text(
        '#!/usr/bin/env bash\nprintf "%s\\n" "$DAY_TEST_TMPDIR"\n',
        encoding="utf-8",
    )
    (fakebin / "mmdc").write_text(
        """#!/usr/bin/env bash
out=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf '%s\\n' '%PDF-1.4 test' > "$out"
""",
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
    (fakebin / "mmdc").chmod(0o755)
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
        "DAYOA_PIPELINE_REPORT_INTERVAL_SECONDS": "1",
        "PYTHONPATH": f"{REPO_ROOT}:{os.environ.get('PYTHONPATH', '')}",
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
    assert (tmp_path / "pipeline_details.md").is_file()
    assert (tmp_path / "pipeline_workflow_planned.mmd").is_file()
    assert (tmp_path / "pipeline_workflow_planned.pdf").is_file()


def test_day_run_sentieon_start_jitter_strips_flag_and_exports_budget(
    tmp_path: Path,
) -> None:
    fakebin = tmp_path / "fakebin"
    profile = tmp_path / "profile"
    capture = tmp_path / "capture"
    fake_tmp = tmp_path / "daytmp"
    fakebin.mkdir()
    profile.mkdir()
    capture.mkdir()
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
printf '%s\\n' "$@" > "$DAY_TEST_CAPTURE/args.txt"
printf '%s\\n' "${DAYOA_SENTIEON_START_JITTER_MAX_SECONDS:-}" > "$DAY_TEST_CAPTURE/jitter.txt"
exit 0
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
DY_IS0=
DY_IS1=
DY_IT1=
DY_IB1=
""",
        encoding="utf-8",
    )

    env = {
        **os.environ,
        "PATH": f"{fakebin}:{os.environ['PATH']}",
        "DAY_ROOT": str(tmp_path),
        "DAY_PROFILE": "test",
        "DAY_PROFILE_DIR": str(profile),
        "DAY_GENOME_BUILD": "hg38",
        "DAY_TEST_TMPDIR": str(fake_tmp),
        "DAY_TEST_CAPTURE": str(capture),
    }

    result = subprocess.run(
        [
            "bash",
            str(REPO_ROOT / "bin/day_run"),
            "--sentieon-start-jitter",
            "produce_test",
            "-j",
            "100",
            "-p",
            "-k",
            "-n",
        ],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    args = (capture / "args.txt").read_text(encoding="utf-8").splitlines()
    assert "--sentieon-start-jitter" not in args
    assert "produce_test" in args
    assert "-j" in args
    assert "100" in args
    assert (capture / "jitter.txt").read_text(encoding="utf-8").strip() == "2"


def test_day_run_sentieon_start_jitter_requires_explicit_jobs(
    tmp_path: Path,
) -> None:
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
        "#!/usr/bin/env bash\nexit 99\n",
        encoding="utf-8",
    )
    (fakebin / "yq").chmod(0o755)
    (fakebin / "snakemake").chmod(0o755)

    (profile / "profile_env.bash").write_text(
        """colr() { printf '%s\\n' "$1" >&2; }
DY_WT0=
DY_WB0=
DY_WS1=
DY_IT1=
DY_IB1=
DY_IS1=
""",
        encoding="utf-8",
    )

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
        ["bash", str(REPO_ROOT / "bin/day_run"), "--sentieon-start-jitter", "help", "-n"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 64
    assert "requires an explicit -j/--jobs/--cores positive integer" in result.stderr


def test_dayoa_sentieon_wrapper_executes_configured_binary(tmp_path: Path) -> None:
    fake_sentieon = tmp_path / "sentieon"
    capture = tmp_path / "sentieon_args.txt"
    fake_sentieon.write_text(
        f"#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > {str(capture)!r}\n",
        encoding="utf-8",
    )
    fake_sentieon.chmod(0o755)

    env = {
        **os.environ,
        "DAYOA_SENTIEON_BIN": str(fake_sentieon),
        "DAYOA_SENTIEON_START_JITTER_MAX_SECONDS": "0",
    }
    result = subprocess.run(
        [str(REPO_ROOT / "bin/dayoa_sentieon"), "driver", "-t", "2"],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert capture.read_text(encoding="utf-8").splitlines() == ["driver", "-t", "2"]


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
    assert (
        "Notice: Cluster config sets aws-parallelcluster-enforce-budget=skip"
        in dyoainit
    )
    assert dyoainit.index(
        'if [[ "$SKIP_PROJECT_CHECK" == true ]]; then'
    ) < dyoainit.index("aws sts get-caller-identity")

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
    assert 'alias day-help="bin/day_run help"' in dyoainit
    assert 'alias dy-h="bin/day_run help"' in dyoainit
    assert 'alias dy-h="echo hello"' not in dyoainit


def test_shell_wrappers_do_not_reference_deprecated_network_overlay() -> None:
    forbidden = (
        "tail" + "scale",
        "headnode-" + "authkey",
        "dayec-headnode-" + "tail",
        "pkgs." + "tail" + "scale" + ".com",
    )

    for path in (
        "dyoainit",
        "bin/day_activate",
        "bin/day_run",
        "bin/augment_setup_and_run_dayoa.bash",
    ):
        text = _read(path).lower()
        for token in forbidden:
            assert token not in text, path


def test_dayoa_environment_declares_mermaid_cli_for_pipeline_reports() -> None:
    day_yaml = _read("config/day/day.yaml")
    installer = _read("config/day/day_env_installer.sh")

    assert "  - nodejs\n" in day_yaml
    assert 'DAYOA_MERMAID_CLI_PACKAGE="@mermaid-js/mermaid-cli@11.15.0"' in installer
    assert '"$CONDA_PREFIX/bin/npm" install --global --prefix "$CONDA_PREFIX" "$DAYOA_MERMAID_CLI_PACKAGE"' in installer
    assert '[[ ! -x "$CONDA_PREFIX/bin/mmdc" ]]' in installer
    assert '"$CONDA_PREFIX/bin/mmdc" --version >/dev/null' in installer
    assert '[[ ! -x "$CONDA_PREFIX/bin/npx" ]]' in installer
    assert "Could not find Chrome" in installer
    assert '@puppeteer/browsers' in installer
    assert 'install "chrome-headless-shell@$mermaid_chrome_version"' in installer
    assert 'mmdc smoke render failed after installing Chrome headless shell.' in installer


def test_mmdc_is_not_called_inside_snakemake_rules() -> None:
    rule_hits = []
    for path in (REPO_ROOT / "workflow" / "rules").rglob("*.smk"):
        if "mmdc" in path.read_text(encoding="utf-8"):
            rule_hits.append(path.relative_to(REPO_ROOT).as_posix())

    assert rule_hits == []
    assert "python -m daylily_omics_analysis.pipeline_reports" in _read("bin/day_run")
    assert 'pdf_path = output_dir / f"pipeline_workflow_{suffix}.pdf"' in _read(
        "daylily_omics_analysis/pipeline_reports.py"
    )


def test_mac_local_activation_contracts() -> None:
    dyoainit = _read("dyoainit")
    day_activate = _read("bin/day_activate")
    local_profile_info = _read("config/day_profiles/local/templates/profile.info")
    local_profile_env = _read("config/day_profiles/local/templates/profile_env.bash")
    profile_warn = _read("bin/util/profile_freshness_warn.bash")

    assert "DAYOA_MAC_LOCAL=false" in dyoainit
    assert 'region="local-mac"' in dyoainit
    assert "macOS local mode requires the DAY-EC or DAYOA conda environment" in dyoainit
    assert "macOS local mode requires the DAYOA conda environment" in dyoainit
    assert "macOS local mode: using conda environment DAYOA." in dyoainit
    assert "source config/day/day_env_installer.sh DAYOA" in dyoainit

    assert (
        'if [[ "${DAY_BIOME:-}" == "MAC" && "$dayp" != "local" ]]; then' in day_activate
    )
    assert 'target_conda_env="DAYOA"' in day_activate
    assert 'target_conda_env="DAY-EC"' not in day_activate
    assert "macOS local mode: using DAYOA while reinitializing DayOA." in day_activate

    assert (
        "env_script:config/day_profiles/local/templates/profile_env.bash"
        in local_profile_info
    )
    assert 'if [[ "${DAY_BIOME:-}" == "MAC" ]]; then' in local_profile_env
    assert "DAYOA_MAC_STATE_DIR" in local_profile_env
    assert "dayoa_sed_inplace()" in profile_warn
    assert 'sed -i.bak "$sed_expr" "$target_file"' in profile_warn


def test_sentieon_license_contracts_fail_hard_without_explicit_config() -> None:
    dyoainit = _read("dyoainit")
    day_activate = _read("bin/day_activate")
    readme = _read("README.md")

    for shell_source in (dyoainit, day_activate):
        assert "find \"$sentieon_license_dir\"" not in shell_source
        assert "auto assigning a detected Sentieon license" not in shell_source
        assert "ls /fsx/references/runtime_assets/cached_envs/*lic" not in shell_source
        assert "daylily.sentieon_lic_path" in shell_source
        assert "return 3" in shell_source

    assert "Sentieon License Configuration" in readme
    assert "sentieon_lic_path" in readme
    assert "/fsx/references/runtime_assets/sentieon/license.lic" in readme
    assert "DayOA does not scan" in readme


def test_shell_wrappers_have_valid_bash_syntax() -> None:
    for path in (
        "bin/day_run",
        "bin/day_activate",
        "bin/day_sentieon_jitter.bash",
        "bin/dayoa_sentieon",
        "bin/dayoa_sentieon_cli",
        "bin/util/profile_freshness_warn.bash",
        "dyoainit",
    ):
        subprocess.run(["bash", "-n", path], cwd=REPO_ROOT, check=True)
