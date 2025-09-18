#!/usr/bin/env bash
# add_sample_id.sh
# Append a 'sampleID' column to a TSV by extracting the path segment
# immediately under results/day/hg38/ from any field in the row.
# If not found, writes 'NA'.
#
# Usage:
#   add_sample_id.sh -i R9test_output_files_summary.txt -o R9test_output_with_sample.tsv
#   # or stream:
#   cat R9test_output_files_summary.txt | add_sample_id.sh > out.tsv
#
# Notes:
# - POSIX awk; no GNU extensions.
# - Scans all fields; first match wins.
# - Robust to absolute/relative paths and extra slashes.

set -eu

in="/dev/stdin"
out="/dev/stdout"

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--input)   in="$2"; shift 2 ;;
    -o|--output)  out="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,200p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

awk -F'\t' -v OFS='\t' '
function trimslashes(s,   r){ r=s; gsub(/\/+/, "/", r); return r }
NR==1 { print $0, "sampleID"; next }
{
  sample="NA"
  for (f=1; f<=NF && sample=="NA"; f++) {
    path = trimslashes($f)
    # split on slashes and scan for results/day/hg38/<SAMPLE>
    n = split(path, p, "/")
    for (i=1; i<=n-3; i++) {
      if (p[i]=="results" && p[i+1]=="day" && p[i+2]=="hg38" && p[i+3]!="") {
        sample = p[i+3]
        break
      }
    }
  }
  print $0, sample
}
' "$in" > "$out"
