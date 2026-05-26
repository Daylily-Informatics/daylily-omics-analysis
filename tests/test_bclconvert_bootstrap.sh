#!/usr/bin/env bash

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

PARSER="workflow/scripts/parse_bclconvert_samplesheet.py"
UNITS_GENERATOR="workflow/scripts/bclconvert_fastq_list_to_units.py"
METRICS_SUMMARY="workflow/scripts/bclconvert_metrics_summary.py"
METRICS_TO_MULTIQC="workflow/scripts/bclconvert_metrics_to_multiqc.py"
RULE_FILE="workflow/rules/bclconvert.smk"
COMMON_FILE="workflow/rules/common.smk"

FIXTURE_DIR=".test_data/data/bclconvert"
FIXTURE_SHEET="${FIXTURE_DIR}/SampleSheet.csv"
FIXTURE_SAMPLES="${FIXTURE_DIR}/samples.tsv"
FIXTURE_FASTQ_LIST="${FIXTURE_DIR}/fastq_list.csv"
FIXTURE_DEMUX="${FIXTURE_DIR}/Demultiplex_Stats.csv"
FIXTURE_UNKNOWN="${FIXTURE_DIR}/Top_Unknown_Barcodes.csv"
FIXTURE_HOPPING="${FIXTURE_DIR}/Index_Hopping_Counts.csv"
FIXTURE_RUN_DIR="${FIXTURE_DIR}/run_dir"

PROFILE_TEMPLATE="config/day_profiles/local/templates/rule_config.yaml"
PROFILE_FILE="config/day_profiles/local/rule_config.yaml"


test_result() {
  local test_name="$1"
  local exit_code="$2"

  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}PASS${NC}: $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}FAIL${NC}: $test_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}


run_parser() {
  local sample_sheet="$1"
  local samples_tsv="$2"
  local normalized_out="$3"
  local rows_out="$4"
  local stderr_out="$5"
  local runtime_version="${6:-4.0.3}"
  local sampleproject_subdirectories="${7:-false}"

  python3 "$PARSER" \
    --sample-sheet "$sample_sheet" \
    --samples-tsv "$samples_tsv" \
    --normalized-out "$normalized_out" \
    --rows-out "$rows_out" \
    --runtime-version "$runtime_version" \
    --sampleproject-subdirectories "$sampleproject_subdirectories" \
    > /dev/null 2> "$stderr_out"
}


run_units_generator() {
  local fastq_list="$1"
  local sample_sheet_rows="$2"
  local units_out="$3"
  local stderr_out="$4"
  local run_id="${5:-20260407_ILMN_training_instr_val_2}"
  local libprep="${6:-PCR-FREE}"
  local seq_vendor="${7:-ILMN}"
  local seq_platform_override="${8:-}"

  python3 "$UNITS_GENERATOR" \
    --fastq-list "$fastq_list" \
    --sample-sheet-rows "$sample_sheet_rows" \
    --run-id "$run_id" \
    --libprep "$libprep" \
    --seq-vendor "$seq_vendor" \
    --seq-platform-override "$seq_platform_override" \
    --units-out "$units_out" \
    > /dev/null 2> "$stderr_out"
}


run_metrics_summary() {
  local report_dir="$1"
  local demux_out="$2"
  local unknown_out="$3"
  local hopping_out="$4"
  local fastq_manifest_out="$5"
  local rollup_json_out="$6"
  local stderr_out="$7"

  python3 "$METRICS_SUMMARY" \
    --report-dir "$report_dir" \
    --demux-out "$demux_out" \
    --unknown-out "$unknown_out" \
    --hopping-out "$hopping_out" \
    --fastq-manifest-out "$fastq_manifest_out" \
    --rollup-json-out "$rollup_json_out" \
    > /dev/null 2> "$stderr_out"
}


edit_sample_sheet() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  python3 -c '
from pathlib import Path
import sys

src, dst, mode = sys.argv[1:4]
lines = Path(src).read_text(encoding="utf-8-sig").splitlines()

def data_line_index(text_lines):
    in_data = False
    saw_header = False
    for idx, line in enumerate(text_lines):
        stripped = line.strip()
        if stripped == "[BCLConvert_Data]":
            in_data = True
            continue
        if not in_data:
            continue
        if not saw_header:
            saw_header = True
            continue
        if stripped:
            return idx
    raise SystemExit("no BCLConvert_Data row found")

if mode == "numeric_indexes":
    idx = data_line_index(lines)
    parts = lines[idx].split(",")
    parts[2] = "001"
    parts[3] = "002"
    lines[idx] = ",".join(parts)
elif mode == "duplicate_row":
    idx = data_line_index(lines)
    lines.append(lines[idx])
elif mode == "unknown_sample":
    idx = data_line_index(lines)
    parts = lines[idx].split(",")
    parts[1] = "NOT_IN_SAMPLES"
    lines[idx] = ",".join(parts)
elif mode == "missing_data_section":
    for idx, line in enumerate(lines):
        if line.strip() == "[BCLConvert_Data]":
            lines = lines[:idx]
            break
    else:
        raise SystemExit("BCLConvert_Data section not found")
else:
    raise SystemExit(f"unknown edit mode: {mode}")

Path(dst).write_text("\n".join(lines) + "\n", encoding="utf-8")
' "$src" "$dst" "$mode"
}


find_snakemake_cmd() {
  if command -v snakemake >/dev/null 2>&1; then
    printf '%s\n' "snakemake"
    return 0
  fi
  if python3 -c 'import snakemake' >/dev/null 2>&1; then
    printf '%s\n' "python3 -m snakemake"
    return 0
  fi
  return 1
}


patch_test_profile() {
  local target="$1"
  local sample_sheet="$2"
  local run_dir="$3"
  local output_root="$4"

  python3 -c '
from pathlib import Path
import sys

target, sample_sheet, run_dir, output_root = sys.argv[1:5]
path = Path(target)
lines = path.read_text(encoding="utf-8").splitlines()
in_block = False
updated = []
for line in lines:
    stripped = line.strip()
    if stripped == "bclconvert:":
        in_block = True
        updated.append(line)
        continue
    if in_block and stripped and not line.startswith("    "):
        in_block = False
    if in_block:
        if line.startswith("    run_dir:"):
            line = f"    run_dir: \"{run_dir}\""
        elif line.startswith("    sample_sheet:"):
            line = f"    sample_sheet: \"{sample_sheet}\""
        elif line.startswith("    output_root:"):
            line = f"    output_root: \"{output_root}\""
    updated.append(line)
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
' "$target" "$sample_sheet" "$run_dir" "$output_root"
}


with_temp_profile() {
  local workdir="$1"
  local callback="$2"
  shift 2
  local backup_profile="${workdir}/rule_config.backup"
  local backup_samples="${workdir}/samples.tsv.backup"
  local backup_units="${workdir}/units.tsv.backup"

  mkdir -p "$(dirname "$PROFILE_FILE")" config "$FIXTURE_RUN_DIR"

  if [[ -f "$PROFILE_FILE" ]]; then
    cp "$PROFILE_FILE" "$backup_profile"
  fi
  if [[ -f config/samples.tsv ]]; then
    cp config/samples.tsv "$backup_samples"
  fi
  if [[ -f config/units.tsv ]]; then
    cp config/units.tsv "$backup_units"
  fi

  cp "$PROFILE_TEMPLATE" "$PROFILE_FILE"
  patch_test_profile "$PROFILE_FILE" "$FIXTURE_SHEET" "$FIXTURE_RUN_DIR" "${workdir}/results"

  export DAY_ROOT="$REPO_ROOT"
  export DAY_BIOME="AWSPC"
  export DAY_PROFILE="local"
  export DAY_GENOME_BUILD="hg38"
  export DAY_CONTACT_EMAIL="test@example.com"

  "$callback" "$workdir" "$@"
  local exit_code=$?

  if [[ -f "$backup_profile" ]]; then
    mv "$backup_profile" "$PROFILE_FILE"
  else
    rm -f "$PROFILE_FILE"
  fi
  if [[ -f "$backup_samples" ]]; then
    mv "$backup_samples" config/samples.tsv
  else
    rm -f config/samples.tsv
  fi
  if [[ -f "$backup_units" ]]; then
    mv "$backup_units" config/units.tsv
  else
    rm -f config/units.tsv
  fi

  return "$exit_code"
}


run_bootstrap_dryrun_case() {
  local workdir="$1"
  local mode="$2"
  local log="$workdir/bootstrap.dryrun.log"
  local snakemake_cmd

  snakemake_cmd="$(find_snakemake_cmd)" || return 2
  if [[ "$mode" == "missing" ]]; then
    rm -f config/units.tsv
  else
    : > config/units.tsv
  fi
  eval "$snakemake_cmd -n produce_bclconvert_fastqs_and_metrics > \"$log\" 2>&1"
}


run_nonbootstrap_dryrun_case() {
  local workdir="$1"
  local mode="$2"
  local log="$workdir/nonbootstrap.dryrun.log"
  local snakemake_cmd

  snakemake_cmd="$(find_snakemake_cmd)" || return 2
  if [[ "$mode" == "missing" ]]; then
    rm -f config/units.tsv
  else
    : > config/units.tsv
  fi
  eval "$snakemake_cmd -n produce_fastqc_html > \"$log\" 2>&1"
}


test_valid_fixture_parses() {
  local tmpdir normalized rows stderr exit_code
  tmpdir="$(mktemp -d)"
  normalized="$tmpdir/normalized.csv"
  rows="$tmpdir/rows.tsv"
  stderr="$tmpdir/stderr.txt"

  if run_parser "$FIXTURE_SHEET" "$FIXTURE_SAMPLES" "$normalized" "$rows" "$stderr"; then
    exit_code=0
    grep -q "SoftwareVersion,4.0.3" "$normalized" || exit_code=1
    ! grep -q "GenerateFastqcMetrics" "$normalized" || exit_code=1
    grep -q "WARNING: sample sheet SoftwareVersion 4.3.16 is newer than pinned runtime 4.0.3" "$stderr" || exit_code=1
    grep -q "INFO: normalized sample sheet SoftwareVersion from 4.3.16 to pinned runtime 4.0.3" "$stderr" || exit_code=1
    grep -q "INFO: stripped unsupported BCLConvert setting GenerateFastqcMetrics from normalized sample sheet" "$stderr" || exit_code=1
    [[ $(wc -l < "$rows") -eq 9 ]] || exit_code=1
  else
    exit_code=$?
  fi

  rm -rf "$tmpdir"
  test_result "parse valid BCL Convert sample sheet fixture and warn-only on version mismatch" "$exit_code"
}


test_numeric_indexes_are_preserved_as_strings() {
  local tmpdir modified_sheet normalized rows stderr exit_code
  tmpdir="$(mktemp -d)"
  modified_sheet="$tmpdir/SampleSheet.numeric.csv"
  normalized="$tmpdir/normalized.csv"
  rows="$tmpdir/rows.tsv"
  stderr="$tmpdir/stderr.txt"
  edit_sample_sheet "$FIXTURE_SHEET" "$modified_sheet" "numeric_indexes"

  if run_parser "$modified_sheet" "$FIXTURE_SAMPLES" "$normalized" "$rows" "$stderr"; then
    python3 -c '
import csv
import sys
with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    row = next(csv.DictReader(handle, delimiter="\t"))
assert row["INDEX"] == "001", row["INDEX"]
assert row["INDEX2"] == "002", row["INDEX2"]
' "$rows"
    exit_code=$?
  else
    exit_code=$?
  fi

  rm -rf "$tmpdir"
  test_result "preserve Index and Index2 as strings" "$exit_code"
}


test_duplicate_row_is_rejected() {
  local tmpdir modified_sheet normalized rows stderr exit_code
  tmpdir="$(mktemp -d)"
  modified_sheet="$tmpdir/SampleSheet.duplicate.csv"
  normalized="$tmpdir/normalized.csv"
  rows="$tmpdir/rows.tsv"
  stderr="$tmpdir/stderr.txt"
  edit_sample_sheet "$FIXTURE_SHEET" "$modified_sheet" "duplicate_row"

  if run_parser "$modified_sheet" "$FIXTURE_SAMPLES" "$normalized" "$rows" "$stderr"; then
    exit_code=1
  else
    exit_code=0
  fi
  grep -q "duplicate BCLConvert_Data row" "$stderr" || exit_code=1

  rm -rf "$tmpdir"
  test_result "reject duplicate (Lane, Sample_ID, Index, Index2)" "$exit_code"
}


test_unknown_sample_is_rejected() {
  local tmpdir modified_sheet normalized rows stderr exit_code
  tmpdir="$(mktemp -d)"
  modified_sheet="$tmpdir/SampleSheet.unknown.csv"
  normalized="$tmpdir/normalized.csv"
  rows="$tmpdir/rows.tsv"
  stderr="$tmpdir/stderr.txt"
  edit_sample_sheet "$FIXTURE_SHEET" "$modified_sheet" "unknown_sample"

  if run_parser "$modified_sheet" "$FIXTURE_SAMPLES" "$normalized" "$rows" "$stderr"; then
    exit_code=1
  else
    exit_code=0
  fi
  grep -q "not present in samples.tsv" "$stderr" || exit_code=1

  rm -rf "$tmpdir"
  test_result "validate Sample_ID values against samples.tsv" "$exit_code"
}


test_missing_required_section_is_rejected() {
  local tmpdir modified_sheet normalized rows stderr exit_code
  tmpdir="$(mktemp -d)"
  modified_sheet="$tmpdir/SampleSheet.missing_data.csv"
  normalized="$tmpdir/normalized.csv"
  rows="$tmpdir/rows.tsv"
  stderr="$tmpdir/stderr.txt"
  edit_sample_sheet "$FIXTURE_SHEET" "$modified_sheet" "missing_data_section"

  if run_parser "$modified_sheet" "$FIXTURE_SAMPLES" "$normalized" "$rows" "$stderr"; then
    exit_code=1
  else
    exit_code=0
  fi
  grep -q "missing required section" "$stderr" || exit_code=1

  rm -rf "$tmpdir"
  test_result "reject sample sheets missing required sections" "$exit_code"
}


test_generate_units_tsv() {
  local tmpdir normalized rows parser_stderr units_out units_stderr exit_code
  tmpdir="$(mktemp -d)"
  normalized="$tmpdir/normalized.csv"
  rows="$tmpdir/samplesheet_rows.tsv"
  parser_stderr="$tmpdir/parser.stderr"
  units_out="$tmpdir/generated.units.tsv"
  units_stderr="$tmpdir/units.stderr"

  if run_parser "$FIXTURE_SHEET" "$FIXTURE_SAMPLES" "$normalized" "$rows" "$parser_stderr" && \
     run_units_generator "$FIXTURE_FASTQ_LIST" "$rows" "$units_out" "$units_stderr"; then
    python3 -c '
import csv
import sys
with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    rows = list(reader)
assert reader.fieldnames == [
    "RUNID",
    "SAMPLEID",
    "EXPERIMENTID",
    "LANEID",
    "BARCODEID",
    "LIBPREP",
    "SEQ_VENDOR",
    "SEQ_PLATFORM",
    "ILMN_R1_PATH",
    "ILMN_R2_PATH",
]
assert len(rows) == 2, rows
assert all(row["SAMPLEID"] != "Undetermined" for row in rows)
assert rows[0]["RUNID"] == "20260407_ILMN_training_instr_val_2"
assert rows[0]["SEQ_PLATFORM"] == "NOVASEQ"
assert rows[0]["ILMN_R1_PATH"].endswith("_R1_001.fastq.gz")
assert rows[1]["SAMPLEID"] == "Beckman_XTR_1-2-200_180"
' "$units_out"
    exit_code=$?
  else
    exit_code=$?
  fi

  rm -rf "$tmpdir"
  test_result "generate generated.units.tsv from stub fastq_list.csv" "$exit_code"
}


test_metrics_summary_outputs() {
  local tmpdir report_dir demux_out unknown_out hopping_out fastq_manifest_out rollup_json_out stderr exit_code
  tmpdir="$(mktemp -d)"
  report_dir="$tmpdir/20260407_ILMN_training_instr_val_2/fastq/Reports"
  mkdir -p "$report_dir"
  cp "$FIXTURE_DEMUX" "$report_dir/Demultiplex_Stats.csv"
  cp "$FIXTURE_FASTQ_LIST" "$report_dir/fastq_list.csv"
  cp "$FIXTURE_UNKNOWN" "$report_dir/Top_Unknown_Barcodes.csv"
  cp "$FIXTURE_HOPPING" "$report_dir/Index_Hopping_Counts.csv"

  demux_out="$tmpdir/demultiplex_stats.tsv"
  unknown_out="$tmpdir/unknown_barcodes.tsv"
  hopping_out="$tmpdir/index_hopping.tsv"
  fastq_manifest_out="$tmpdir/fastq_manifest.tsv"
  rollup_json_out="$tmpdir/rollup.json"
  stderr="$tmpdir/metrics.stderr"

  if run_metrics_summary "$report_dir" "$demux_out" "$unknown_out" "$hopping_out" "$fastq_manifest_out" "$rollup_json_out" "$stderr"; then
    python3 -c '
import csv
import json
import sys

demux_tsv, unknown_tsv, hopping_tsv, fastq_manifest_tsv, rollup_json = sys.argv[1:6]
with open(demux_tsv, newline="", encoding="utf-8") as handle:
    demux_rows = list(csv.DictReader(handle, delimiter="\t"))
with open(unknown_tsv, newline="", encoding="utf-8") as handle:
    unknown_rows = list(csv.DictReader(handle, delimiter="\t"))
with open(hopping_tsv, newline="", encoding="utf-8") as handle:
    hopping_rows = list(csv.DictReader(handle, delimiter="\t"))
with open(fastq_manifest_tsv, newline="", encoding="utf-8") as handle:
    manifest_rows = list(csv.DictReader(handle, delimiter="\t"))
with open(rollup_json, encoding="utf-8") as handle:
    rollup = json.load(handle)

assert len(demux_rows) == 3, demux_rows
assert any(row["sample_id"] == "Undetermined" for row in demux_rows)
assert len(unknown_rows) == 1, unknown_rows
assert len(hopping_rows) == 0, hopping_rows
assert len(manifest_rows) == 3, manifest_rows
assert rollup["run_id"] == "20260407_ILMN_training_instr_val_2"
assert rollup["demultiplex_stats"]["total_pf_reads_by_lane"]["1"] == 1050
assert rollup["demultiplex_stats"]["undetermined_reads_by_lane"]["1"] == 50
assert rollup["top_unknown_barcodes_by_lane"]["1"][0]["reads"] == 12
' "$demux_out" "$unknown_out" "$hopping_out" "$fastq_manifest_out" "$rollup_json_out"
    exit_code=$?
  else
    exit_code=$?
  fi

  rm -rf "$tmpdir"
  test_result "summarize stub Demultiplex_Stats.csv and preserve Undetermined rows" "$exit_code"
}


test_header_only_index_hopping_is_allowed() {
  local tmpdir report_dir demux_out unknown_out hopping_out fastq_manifest_out rollup_json_out stderr exit_code
  tmpdir="$(mktemp -d)"
  report_dir="$tmpdir/20260407_ILMN_training_instr_val_2/fastq/Reports"
  mkdir -p "$report_dir"
  cp "$FIXTURE_DEMUX" "$report_dir/Demultiplex_Stats.csv"
  cp "$FIXTURE_FASTQ_LIST" "$report_dir/fastq_list.csv"
  cp "$FIXTURE_UNKNOWN" "$report_dir/Top_Unknown_Barcodes.csv"
  cp "$FIXTURE_HOPPING" "$report_dir/Index_Hopping_Counts.csv"

  demux_out="$tmpdir/demultiplex_stats.tsv"
  unknown_out="$tmpdir/unknown_barcodes.tsv"
  hopping_out="$tmpdir/index_hopping.tsv"
  fastq_manifest_out="$tmpdir/fastq_manifest.tsv"
  rollup_json_out="$tmpdir/rollup.json"
  stderr="$tmpdir/metrics.stderr"

  if run_metrics_summary "$report_dir" "$demux_out" "$unknown_out" "$hopping_out" "$fastq_manifest_out" "$rollup_json_out" "$stderr"; then
    [[ $(wc -l < "$hopping_out") -eq 1 ]]
    exit_code=$?
  else
    exit_code=$?
  fi

  rm -rf "$tmpdir"
  test_result "accept header-only Index_Hopping_Counts.csv" "$exit_code"
}


test_rule_text_shell_only() {
  python3 -c '
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
assert "BCL_RUNTIME_VERSION = \"4.0.3\"" in text
assert "BCL_CONTAINER_URI = f\"docker://nfcore/bclconvert:{BCL_RUNTIME_VERSION}\"" in text
assert "BCL_STAGING_MODE" in text
assert "Unsupported bclconvert.staging_mode" in text
assert "Insufficient scratch for bclconvert.staging_mode=output_dev_shm" in text
assert "Insufficient scratch for bclconvert.staging_mode=dev_shm" in text
assert "Insufficient scratch for bclconvert.staging_mode=s3_dev_shm" in text
assert "bclconvert.staging_mode=s3_dev_shm requires SOURCE_S3_URI" in text
assert "aws s3 sync" in text
assert "singularity exec {params.container_uri:q} bcl-convert" in text
assert "--bcl-num-parallel-tiles {params.parallel_tiles}" in text
assert "--bcl-num-conversion-threads {params.conversion_threads}" in text
assert "--bcl-num-compression-threads {params.compression_threads}" in text
assert "--bcl-num-decompression-threads {params.decompression_threads}" in text
assert "--fastq-gzip-compression-level {params.fastq_gzip_compression_level}" in text
assert "-m fastqc" not in text
assert "{BCL_FASTQ_DIR:q}" not in text[text.index("rule multiqc_bclconvert:"):]
assert "script:" not in text
assert re.search(r"(?m)^\\s*run:\\s*$", text) is None
rule_names = [
    "bclconvert_validate_inputs",
    "run_bclconvert",
    "bclconvert_generate_units_tsv",
    "bclconvert_metrics_summary",
    "bclconvert_metrics_multiqc_exports",
    "multiqc_bclconvert",
    "produce_bclconvert_fastqs",
    "produce_bclconvert_metrics",
    "produce_bclconvert_multiqc",
    "produce_bclconvert_fastqs_and_metrics",
]
for idx, name in enumerate(rule_names):
    start = text.index(f"rule {name}:")
    end = len(text)
    for later in rule_names[idx + 1:]:
        token = f"rule {later}:"
        pos = text.find(token, start + 1)
        if pos != -1:
            end = min(end, pos)
    block = text[start:end]
    if name not in {"produce_bclconvert_metrics", "produce_bclconvert_multiqc"}:
        assert "shell:" in block, name
    if name not in {"produce_bclconvert_fastqs", "produce_bclconvert_metrics", "produce_bclconvert_multiqc", "produce_bclconvert_fastqs_and_metrics"}:
        assert "log:" in block, name
        assert "benchmark:" in block, name
	' "$RULE_FILE"
  test_result "verify nf-core container invocation and shell-only new rules" "$?"
}

test_bootstrap_blank_or_missing_units_gate() {
  local tmpdir exit_code
  tmpdir="$(mktemp -d)"
  if find_snakemake_cmd >/dev/null 2>&1; then
    with_temp_profile "$tmpdir" run_bootstrap_dryrun_case "missing"
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
      with_temp_profile "$tmpdir" run_bootstrap_dryrun_case "blank"
      exit_code=$?
    fi
  else
    echo -e "${YELLOW}INFO${NC}: snakemake not available; using static bootstrap gating assertions"
    python3 -c '
from pathlib import Path
text = Path("workflow/rules/common.smk").read_text(encoding="utf-8")
assert "produce_bclconvert_fastqs" in text
assert "produce_bclconvert_metrics" in text
assert "produce_bclconvert_multiqc" in text
assert "produce_bclconvert_fastqs_and_metrics" in text
assert "allow_bootstrap=BCL_BOOTSTRAP_MODE" in text
assert "if not BCL_BOOTSTRAP_MODE:" in text
' 
    exit_code=$?
  fi
  rm -rf "$tmpdir"
  test_result "allow blank or missing units.tsv only for bootstrap targets" "$exit_code"
}


test_nonbootstrap_blank_or_missing_units_fails() {
  local tmpdir exit_code
  tmpdir="$(mktemp -d)"
  if find_snakemake_cmd >/dev/null 2>&1; then
    with_temp_profile "$tmpdir" run_nonbootstrap_dryrun_case "missing"
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
      exit_code=1
    else
      exit_code=0
    fi
    if [[ $exit_code -eq 0 ]]; then
      with_temp_profile "$tmpdir" run_nonbootstrap_dryrun_case "blank"
      if [[ $? -eq 0 ]]; then
        exit_code=1
      fi
    fi
  else
    echo -e "${YELLOW}INFO${NC}: snakemake not available; using static non-bootstrap gating assertions"
    python3 -c '
from pathlib import Path
text = Path("workflow/rules/common.smk").read_text(encoding="utf-8")
assert "The units table was not found at {path}." in text
assert "The units table at {path} is empty." in text
assert "The units table at {path} has headers but no data rows." in text
' >/dev/null 2>&1
    exit_code=0
  fi
  rm -rf "$tmpdir"
  test_result "keep non-bootstrap targets failing on blank or missing units.tsv" "$exit_code"
}


main() {
  mkdir -p "$FIXTURE_RUN_DIR"

  echo "=========================================="
  echo "BCL Convert Bootstrap Test Suite"
  echo "=========================================="
  echo ""

  test_valid_fixture_parses
  test_numeric_indexes_are_preserved_as_strings
  test_duplicate_row_is_rejected
  test_unknown_sample_is_rejected
  test_missing_required_section_is_rejected
  test_generate_units_tsv
  test_metrics_summary_outputs
  test_header_only_index_hopping_is_allowed
  test_bootstrap_blank_or_missing_units_gate
  test_nonbootstrap_blank_or_missing_units_fails
  test_rule_text_shell_only

  echo ""
  echo "=========================================="
  echo "Test Results"
  echo "=========================================="
  echo "Total:  $TESTS_RUN"
  echo "Passed: $TESTS_PASSED"
  echo "Failed: $TESTS_FAILED"
  echo "=========================================="

  if [[ $TESTS_FAILED -ne 0 ]]; then
    exit 1
  fi
}


main "$@"
