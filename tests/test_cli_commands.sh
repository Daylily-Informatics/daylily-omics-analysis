#!/usr/bin/env bash
# Test suite for Daylily CLI commands
# Tests: day-activate, day-run, day-monitor, day-set-genome-build, day-deactivate, dy-* links

set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test results
test_result() {
  local test_name="$1"
  local exit_code="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS${NC}: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗ FAIL${NC}: $test_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

create_fake_squeue() {
  local fakebin="$1"

  mkdir -p "$fakebin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo "JOBID PARTITION NAME USER ST TIME NODES NODELIST(REASON)"' \
    > "$fakebin/squeue"
  chmod +x "$fakebin/squeue"
}

# Test 1: day-monitor help
test_day_monitor_help() {
  bin/day_monitor --help > /tmp/test_monitor_help.txt 2>&1
  grep -q "Monitor Daylily analysis workflow status" /tmp/test_monitor_help.txt
  test_result "day-monitor --help" $?
}

# Test 2: day-monitor help (short form)
test_day_monitor_help_short() {
  bin/day_monitor -h > /tmp/test_monitor_help_short.txt 2>&1
  grep -q "Usage: day-monitor" /tmp/test_monitor_help_short.txt
  test_result "day-monitor -h" $?
}

# Test 3: day-monitor validates workdir
test_day_monitor_invalid_workdir() {
  bin/day_monitor --workdir /nonexistent/path 2>&1 | grep -q "ERROR: Workdir does not exist"
  test_result "day-monitor validates workdir" $?
}

# Test 4: day-monitor accepts --interval
test_day_monitor_interval_option() {
  # Just verify the option is accepted (don't run the monitor)
  bin/day_monitor --help | grep -q "\-\-interval"
  test_result "day-monitor accepts --interval option" $?
}

# Test 5: day-monitor accepts --block-and-poll
test_day_monitor_block_and_poll_option() {
  bin/day_monitor --help | grep -q "\-\-block-and-poll"
  test_result "day-monitor accepts --block-and-poll option" $?
}

# Test 6: day-monitor accepts --workdir
test_day_monitor_workdir_option() {
  bin/day_monitor --help | grep -q "\-\-workdir"
  test_result "day-monitor accepts --workdir option" $?
}

# Test 7: day-monitor reads day_cmd.log
test_day_monitor_reads_day_cmd_log() {
  local tmpdir
  local fakebin
  tmpdir=$(mktemp -d)
  fakebin="$tmpdir/fakebin"

  create_fake_squeue "$fakebin"

  printf 'dy-r produce_alignstats -p -j 1\n' > "$tmpdir/day_cmd.log"
  touch "$tmpdir/daylily.successful_run"

  TERM=xterm PATH="$fakebin:$PATH" bin/day_monitor --workdir "$tmpdir" --block-and-poll > /tmp/test_monitor_cmd_log.txt 2>&1
  grep -q 'dy-r produce_alignstats -p -j 1' /tmp/test_monitor_cmd_log.txt
  local exit_code=$?

  rm -rf "$tmpdir"
  test_result "day-monitor reads day_cmd.log" $exit_code
}

# Test 8: day-monitor keeps polling until workflow completes
test_day_monitor_block_and_poll_waits() {
  local tmpdir
  local fakebin
  local monitor_pid
  local exit_code

  tmpdir=$(mktemp -d)
  fakebin="$tmpdir/fakebin"

  create_fake_squeue "$fakebin"
  printf 'dy-r produce_alignstats -p -j 1\n' > "$tmpdir/day_cmd.log"

  TERM=xterm PATH="$fakebin:$PATH" bin/day_monitor --workdir "$tmpdir" --interval 1 --block-and-poll > /tmp/test_monitor_block_and_poll.txt 2>&1 &
  monitor_pid=$!

  sleep 2
  touch "$tmpdir/daylily.successful_run"

  wait "$monitor_pid"
  exit_code=$?

  if [[ $exit_code -eq 0 ]] && grep -q "Workflow completed successfully" /tmp/test_monitor_block_and_poll.txt; then
    exit_code=0
  else
    exit_code=1
  fi

  rm -rf "$tmpdir"
  test_result "day-monitor block-and-poll waits for completion" $exit_code
}

# Test 9: day-activate script exists (sourced, not executed)
test_day_activate_exists() {
  [[ -f bin/day_activate ]]
  test_result "day-activate exists" $?
}

# Test 10: day-run script exists and is executable
test_day_run_exists() {
  [[ -x bin/day_run ]]
  test_result "day-run exists and is executable" $?
}

# Test 11: day-run reports package version without requiring activation
test_day_run_version() {
  local expected
  local exit_code

  expected=$(python -c 'from importlib.metadata import version; print("daylily-omics-analysis " + version("daylily-omics-analysis"))')
  bin/day_run --version > /tmp/test_day_run_version.txt 2>&1
  exit_code=$?

  if [[ $exit_code -eq 0 ]] && grep -qx "$expected" /tmp/test_day_run_version.txt; then
    exit_code=0
  else
    exit_code=1
  fi

  test_result "day-run --version" $exit_code
}

# Test 12: day-set-genome-build script exists (sourced, not executed)
test_day_set_genome_build_exists() {
  [[ -f bin/day_set_genome_build ]]
  test_result "day-set-genome-build exists" $?
}

# Test 13: day-deactivate script exists (sourced, not executed)
test_day_deactivate_exists() {
  [[ -f bin/day_deactivate ]]
  test_result "day-deactivate exists" $?
}

# Test 14: dyoainit does not define DayOA aliases
test_dyoainit_has_no_dayoa_aliases() {
  ! grep -qE '^alias (day-|dy-)' dyoainit
  test_result "dyoainit has no DayOA aliases" $?
}

# Test 15: dy-* commands are bin links
test_dy_command_links() {
  [[ "$(readlink bin/dy-a)" == "day_activate" ]] &&
    [[ -x bin/dy-a ]] &&
    [[ "$(readlink bin/dy-d)" == "day_deactivate" ]] &&
    [[ -x bin/dy-d ]] &&
    [[ "$(readlink bin/dy-g)" == "day_set_genome_build" ]] &&
    [[ -x bin/dy-g ]] &&
    [[ "$(readlink bin/dy-h)" == "day_help" ]] &&
    [[ -x bin/dy-h ]] &&
    [[ "$(readlink bin/dy-m)" == "day_monitor" ]] &&
    [[ -x bin/dy-m ]] &&
    [[ "$(readlink bin/dy-r)" == "day_run" ]] &&
    [[ -x bin/dy-r ]]
  test_result "dy-* commands are bin links" $?
}

# Test 16: tabcomp.bash has monitor completion
test_tabcomp_monitor_completion() {
  grep -q '_dym()' bin/tabcomp.bash
  test_result "tabcomp.bash has monitor completion function" $?
}

# Test 17: tabcomp.bash registers monitor completion
test_tabcomp_monitor_registration() {
  grep -q 'complete -F _dym day-monitor dy-m' bin/tabcomp.bash
  test_result "tabcomp.bash registers monitor completion" $?
}

# Test 18: tabcomp.bash includes day-run --version completion
test_tabcomp_day_run_version_completion() {
  grep -q -- '--version' bin/tabcomp.bash
  test_result "tabcomp.bash completes day-run --version" $?
}

# Test 19: day-monitor script is valid bash
test_day_monitor_bash_syntax() {
  bash -n bin/day_monitor 2>&1
  test_result "day-monitor has valid bash syntax" $?
}

# Test 20: day-activate script is valid bash
test_day_activate_bash_syntax() {
  bash -n bin/day_activate 2>&1
  test_result "day-activate has valid bash syntax" $?
}

# Test 21: day-run script is valid bash
test_day_run_bash_syntax() {
  bash -n bin/day_run 2>&1
  test_result "day-run has valid bash syntax" $?
}

# Test 22: AGENTS.md documents monitor command
test_agents_md_monitor_docs() {
  grep -q "Log Locations for SLURM-based Workflows" AGENTS.md
  test_result "AGENTS.md documents SLURM log locations" $?
}

# Test 23: AGENTS.md documents SSM-only headnode access
test_agents_md_ssm_docs() {
  grep -q "SSM is the only supported access model" AGENTS.md &&
    grep -q "Do not use direct SSH" AGENTS.md
  test_result "AGENTS.md documents SSM-only headnode access" $?
}

# Test 24: dycli.md documents monitor command
test_dycli_md_monitor_docs() {
  grep -q "day-monitor" docs/ops/dycli.md
  test_result "dycli.md documents day-monitor command" $?
}

# Test 25: dycli.md documents day-run --version
test_dycli_md_version_docs() {
  grep -q -- '--version' docs/ops/dycli.md
  test_result "dycli.md documents day-run --version" $?
}

# Test 26: day-activate reinitializes the sourced dyoainit environment
test_day_activate_reinitializes_dyoainit() {
  grep -q 'source ./dyoainit --project "$DP" --skip-project-check' bin/day_activate &&
    ! grep -q 'dyoainit --project $DP --deactivate' bin/day_activate
  test_result "day-activate reinitializes dyoainit instead of deactivating it" $?
}

# Test 27: day-activate uses an explicit DAY_PROJECT default when missing
test_day_activate_defaults_missing_day_project_to_global() {
  grep -q 'DP="${DAY_PROJECT:-global}"' bin/day_activate &&
    ! grep -q 'DAY_PROJECT is not set' bin/day_activate
  test_result "day-activate defaults missing DAY_PROJECT to global" $?
}

# Test 28: dyoainit can resolve the user when SSM omits USER
test_dyoainit_resolves_user_with_id_un() {
  grep -q 'day_current_user()' dyoainit &&
    grep -q 'id -un' dyoainit &&
    grep -q 'DAY_USER="$(day_current_user)"' dyoainit &&
    grep -q 'export USER="${USER:-$DAY_USER}"' dyoainit
  test_result "dyoainit resolves missing USER from id -un" $?
}

# Main test execution
main() {
  echo "=========================================="
  echo "Daylily CLI Command Test Suite"
  echo "=========================================="
  echo ""
  
  # Run all tests
  test_day_monitor_help
  test_day_monitor_help_short
  test_day_monitor_invalid_workdir
  test_day_monitor_interval_option
  test_day_monitor_block_and_poll_option
  test_day_monitor_workdir_option
  test_day_monitor_reads_day_cmd_log
  test_day_monitor_block_and_poll_waits
  test_day_activate_exists
  test_day_run_exists
  test_day_run_version
  test_day_set_genome_build_exists
  test_day_deactivate_exists
  test_dyoainit_has_no_dayoa_aliases
  test_dy_command_links
  test_tabcomp_monitor_completion
  test_tabcomp_monitor_registration
  test_tabcomp_day_run_version_completion
  test_day_monitor_bash_syntax
  test_day_activate_bash_syntax
  test_day_run_bash_syntax
  test_agents_md_monitor_docs
  test_agents_md_ssm_docs
  test_dycli_md_monitor_docs
  test_dycli_md_version_docs
  test_day_activate_reinitializes_dyoainit
  test_day_activate_defaults_missing_day_project_to_global
  test_dyoainit_resolves_user_with_id_un
  
  echo ""
  echo "=========================================="
  echo "Test Results"
  echo "=========================================="
  echo "Total:  $TESTS_RUN"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo "=========================================="
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
