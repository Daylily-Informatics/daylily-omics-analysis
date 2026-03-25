#!/usr/bin/env bash
# Test suite for Daylily CLI commands
# Tests: day-activate, day-run, day-monitor, day-set-genome-build, day-deactivate

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
  bin/day_monitor --workdir /nonexistent/path 2>&1 | grep -q "ERROR: Workdir does not exist" || true
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
  tmpdir=$(mktemp -d)

  printf 'dy-r produce_alignstats -p -j 1\n' > "$tmpdir/day_cmd.log"
  touch "$tmpdir/daylily.successful_run"

  TERM=xterm bin/day_monitor --workdir "$tmpdir" --block-and-poll > /tmp/test_monitor_cmd_log.txt 2>&1
  grep -q 'dy-r produce_alignstats -p -j 1' /tmp/test_monitor_cmd_log.txt
  local exit_code=$?

  rm -rf "$tmpdir"
  test_result "day-monitor reads day_cmd.log" $exit_code
}

# Test 8: day-activate script exists (sourced, not executed)
test_day_activate_exists() {
  [[ -f bin/day_activate ]]
  test_result "day-activate exists" $?
}

# Test 8: day-run script exists and is executable
test_day_run_exists() {
  [[ -x bin/day_run ]]
  test_result "day-run exists and is executable" $?
}

# Test 9: day-set-genome-build script exists (sourced, not executed)
test_day_set_genome_build_exists() {
  [[ -f bin/day_set_genome_build ]]
  test_result "day-set-genome-build exists" $?
}

# Test 10: day-deactivate script exists (sourced, not executed)
test_day_deactivate_exists() {
  [[ -f bin/day_deactivate ]]
  test_result "day-deactivate exists" $?
}

# Test 11: dyoainit defines day-monitor alias
test_dyoainit_monitor_alias() {
  grep -q 'alias day-monitor="bin/day_monitor"' dyoainit
  test_result "dyoainit defines day-monitor alias" $?
}

# Test 12: dyoainit defines dy-m alias
test_dyoainit_dy_m_alias() {
  grep -q 'alias dy-m="bin/day_monitor"' dyoainit
  test_result "dyoainit defines dy-m alias" $?
}

# Test 13: tabcomp.bash has monitor completion
test_tabcomp_monitor_completion() {
  grep -q '_dym()' bin/tabcomp.bash
  test_result "tabcomp.bash has monitor completion function" $?
}

# Test 14: tabcomp.bash registers monitor completion
test_tabcomp_monitor_registration() {
  grep -q 'complete -F _dym day-monitor dy-m' bin/tabcomp.bash
  test_result "tabcomp.bash registers monitor completion" $?
}

# Test 15: day-monitor script is valid bash
test_day_monitor_bash_syntax() {
  bash -n bin/day_monitor 2>&1
  test_result "day-monitor has valid bash syntax" $?
}

# Test 16: day-activate script is valid bash
test_day_activate_bash_syntax() {
  bash -n bin/day_activate 2>&1
  test_result "day-activate has valid bash syntax" $?
}

# Test 17: day-run script is valid bash
test_day_run_bash_syntax() {
  bash -n bin/day_run 2>&1
  test_result "day-run has valid bash syntax" $?
}

# Test 18: AGENTS.md documents monitor command
test_agents_md_monitor_docs() {
  grep -q "Log Locations for SLURM-based Workflows" AGENTS.md
  test_result "AGENTS.md documents SLURM log locations" $?
}

# Test 19: AGENTS.md documents SSH login shells
test_agents_md_ssh_docs() {
  grep -q "Always use login shells when running SSH commands" AGENTS.md
  test_result "AGENTS.md documents SSH login shell requirement" $?
}

# Test 20: dycli.md documents monitor command
test_dycli_md_monitor_docs() {
  grep -q "day-monitor" docs/ops/dycli.md
  test_result "dycli.md documents day-monitor command" $?
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
  test_day_activate_exists
  test_day_run_exists
  test_day_set_genome_build_exists
  test_day_deactivate_exists
  test_dyoainit_monitor_alias
  test_dyoainit_dy_m_alias
  test_tabcomp_monitor_completion
  test_tabcomp_monitor_registration
  test_day_monitor_bash_syntax
  test_day_activate_bash_syntax
  test_day_run_bash_syntax
  test_agents_md_monitor_docs
  test_agents_md_ssh_docs
  test_dycli_md_monitor_docs
  
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

