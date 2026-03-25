# Daylily CLI Tests

This directory contains test suites for the Daylily CLI commands.

## Test Files

### `test_cli_commands.sh`

Comprehensive test suite for all CLI commands and their integration.

**Tests covered:**
- `day-monitor` / `dy-m` command functionality
  - Help documentation
  - Option parsing (--workdir, --interval, --block-and-poll)
  - Workdir validation
- `day-activate` / `dy-a` command
- `day-run` / `dy-r` command
- `day-set-genome-build` / `dy-g` command
- `day-deactivate` / `dy-d` command
- CLI aliases in `dyoainit`
- Tab completion in `bin/tabcomp.bash`
- Bash syntax validation
- Documentation coverage in AGENTS.md and docs/ops/dycli.md

**Running the tests:**

```bash
# From repository root
bash tests/test_cli_commands.sh

# Expected output: All 21 tests should pass
```

## Test Results

```
==========================================
Daylily CLI Command Test Suite
==========================================

✓ PASS: day-monitor --help
✓ PASS: day-monitor -h
✓ PASS: day-monitor validates workdir
✓ PASS: day-monitor accepts --interval option
✓ PASS: day-monitor accepts --block-and-poll option
✓ PASS: day-monitor accepts --workdir option
✓ PASS: day-activate exists
✓ PASS: day-run exists and is executable
✓ PASS: day-set-genome-build exists
✓ PASS: day-deactivate exists
✓ PASS: dyoainit defines day-monitor alias
✓ PASS: dyoainit defines dy-m alias
✓ PASS: tabcomp.bash has monitor completion function
✓ PASS: tabcomp.bash registers monitor completion
✓ PASS: day-monitor has valid bash syntax
✓ PASS: day-activate has valid bash syntax
✓ PASS: day-run has valid bash syntax
✓ PASS: AGENTS.md documents SLURM log locations
✓ PASS: AGENTS.md documents SSH login shell requirement
✓ PASS: dycli.md documents day-monitor command

==========================================
Test Results
==========================================
Total:  21
Passed: 21
Failed: 0
==========================================
```

## Adding New Tests

To add new tests:

1. Create a test function following the pattern:
   ```bash
   test_my_feature() {
     # Test logic here
     test_result "Description of test" $?
   }
   ```

2. Call the function in the `main()` function

3. Run the test suite to verify

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```bash
# Exit code 0 = all tests passed
# Exit code 1 = one or more tests failed
bash tests/test_cli_commands.sh
echo $?
```

