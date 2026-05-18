#!/usr/bin/env bash
set -euo pipefail

BASE=/fsx/run_dir_mounts
ROOT_OUT=/fsx/analysis_results/ubuntu/run_qc_illumina_all
COMBINED_INPUTS="$ROOT_OUT/_combined_inputs"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

find_bcl_reports_dir() {
  local run_dir="$1"
  local candidate
  local matches
  local match_count

  for candidate in \
    "$run_dir/Analysis/1/Data/BCLConvert/fastq/Reports" \
    "$run_dir/Analysis/1/Data/BCLConvert/Reports" \
    "$run_dir/Analysis/1/Data/Demux"
  do
    if [ -s "$candidate/Demultiplex_Stats.csv" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  matches="$(find "$run_dir/Analysis" -type f -name 'Demultiplex_Stats.csv' 2>/dev/null | sort || true)"
  match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [ "$match_count" = "0" ]; then
    return 1
  fi

  if [ "$match_count" != "1" ]; then
    echo "Ambiguous Demultiplex_Stats.csv locations for $run_dir:" >&2
    printf '%s\n' "$matches" >&2
    return 2
  fi

  dirname "$(printf '%s\n' "$matches" | sed -n '1p')"
}

prefix_csv_samples() {
  local run_id="$1"
  local src="$2"
  local dest="$3"

  mkdir -p "$(dirname "$dest")"

  python -c '
import csv
import sys

run_id, src, dest = sys.argv[1:4]
sample_headers = {
    "sampleid",
    "sample_id",
    "sample id",
    "sample name",
    "samplename",
    "sample_name",
}

with open(src, newline="", encoding="utf-8-sig") as fin:
    reader = csv.reader(fin)
    try:
        header = next(reader)
    except StopIteration:
        raise SystemExit(f"empty CSV: {src}")

    sample_cols = [
        i for i, name in enumerate(header)
        if name.strip().lower() in sample_headers
    ]

    with open(dest, "w", newline="", encoding="utf-8") as fout:
        writer = csv.writer(fout, lineterminator="\n")
        writer.writerow(header)

        for row in reader:
            for i in sample_cols:
                if i < len(row):
                    value = row[i].strip()
                    if value and not value.startswith(run_id + "-"):
                        row[i] = run_id + "-" + value
            writer.writerow(row)
' "$run_id" "$src" "$dest"
}

require_cmd interop_summary
require_cmd interop_index-summary
require_cmd checkqc
require_cmd multiqc
require_cmd python

mkdir -p "$ROOT_OUT"
rm -rf "$COMBINED_INPUTS"
mkdir -p "$COMBINED_INPUTS"

for RUN_DIR in "$BASE"/*/; do
  RUN_DIR="${RUN_DIR%/}"
  RUN_ID="$(basename "$RUN_DIR")"
  OUT="$ROOT_OUT/$RUN_ID"
  RUN_INPUTS="$OUT/multiqc_inputs"
  COMBINED_RUN_INPUTS="$COMBINED_INPUTS/$RUN_ID/multiqc_inputs"

  echo "Processing $RUN_ID"

  test -s "$RUN_DIR/RunInfo.xml" || {
    echo "Skipping $RUN_ID: missing RunInfo.xml" >&2
    continue
  }

  rm -rf "$RUN_INPUTS" "$COMBINED_RUN_INPUTS"
  mkdir -p \
    "$RUN_INPUTS"/{interop,checkqc,bclconvert} \
    "$COMBINED_RUN_INPUTS"/{interop,checkqc,bclconvert}

  interop_summary "$RUN_DIR" --csv=1 > "$RUN_INPUTS/interop/interop_summary.csv"
  interop_index-summary "$RUN_DIR" --csv=1 > "$RUN_INPUTS/interop/interop_index_summary.csv"
  checkqc --json "$RUN_DIR" > "$RUN_INPUTS/checkqc/checkqc.json"

  cp "$RUN_INPUTS/interop/interop_summary.csv" \
    "$COMBINED_RUN_INPUTS/interop/${RUN_ID}_interop_summary.csv"

  cp "$RUN_INPUTS/interop/interop_index_summary.csv" \
    "$COMBINED_RUN_INPUTS/interop/${RUN_ID}_interop_index_summary.csv"

  cp "$RUN_INPUTS/checkqc/checkqc.json" \
    "$COMBINED_RUN_INPUTS/checkqc/${RUN_ID}_checkqc.json"

  if BCL_REPORTS="$(find_bcl_reports_dir "$RUN_DIR")"; then
    echo "Using BCLConvert reports for $RUN_ID: $BCL_REPORTS"

    ln -sf "$RUN_DIR/RunInfo.xml" "$RUN_INPUTS/bclconvert/RunInfo.xml"
    ln -sf "$RUN_DIR/RunInfo.xml" "$COMBINED_RUN_INPUTS/bclconvert/RunInfo.xml"

    for f in \
      Demultiplex_Stats.csv \
      Quality_Metrics.csv \
      Adapter_Metrics.csv \
      Top_Unknown_Barcodes.csv \
      Index_Hopping_Counts.csv \
      fastq_list.csv
    do
      if [ -e "$BCL_REPORTS/$f" ]; then
        ln -sf "$BCL_REPORTS/$f" "$RUN_INPUTS/bclconvert/$f"
      fi
    done

    for csv in "$RUN_INPUTS"/bclconvert/*.csv; do
      [ -e "$csv" ] || continue
      prefix_csv_samples "$RUN_ID" "$csv" "$COMBINED_RUN_INPUTS/bclconvert/$(basename "$csv")"
    done
  else
    rc=$?
    if [ "$rc" = "2" ]; then
      exit 1
    fi
    echo "No BCLConvert demux metrics for $RUN_ID; InterOp/CheckQC only" >&2
  fi

  multiqc -f \
    -m interop \
    -m checkqc \
    -m bclconvert \
    --filename "${RUN_ID}.multiqc.html" \
    --outdir "$OUT" \
    "$RUN_INPUTS"
done

multiqc -f \
  -m interop \
  -m checkqc \
  -m bclconvert \
  --dirs \
  --filename illumina_runs.multiqc.html \
  --outdir "$ROOT_OUT" \
  "$COMBINED_INPUTS"
