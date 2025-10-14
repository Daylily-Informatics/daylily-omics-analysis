#!/usr/bin/env bash
set -euo pipefail

awk -F'\t' 'NR>1{print $1}' smn_fetch_table.tsv | sort -u > samples.txt


# ------------------------------------------------------------
# fqfetch.sh  — Fetch FASTQs for 1000G/Coriell samples using wget + GNU parallel
# ------------------------------------------------------------
# Usage:
#   fqfetch.sh <samples.txt|smn_fetch_table.tsv> <out_dir> [--tsv] [--parallel N]
# Examples:
#   fqfetch.sh samples.txt /fsx/fastq --parallel 8
#   fqfetch.sh smn_fetch_table.tsv /fsx/fastq --tsv
# ------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  fqfetch.sh <samples.txt|smn_fetch_table.tsv> <out_dir> [--tsv] [--parallel N]

  --tsv        interpret first column (SampleID) of TSV file
  --parallel N number of samples to download concurrently (default 4)
Notes:
  - requires wget and GNU parallel
  - reads ./<SampleID>/urls.txt (if exists) or builds one from ENA API
EOF
}

if [[ $# -lt 2 ]]; then usage; exit 2; fi
INPUT="$1"; OUT="${2%/}"; shift 2
IS_TSV=0; PARALLEL=4

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tsv) IS_TSV=1 ;;
    --parallel) PARALLEL="${2:-4}"; shift ;;
    *) echo "WARN: unknown flag $1" >&2 ;;
  esac
  shift
done

mkdir -p "$OUT"

ENA_BASE="https://www.ebi.ac.uk/ena/portal/api/search"

ena_fastq_q() {
  local s="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp&query=sample_alias%%3D%%22%s%%22%%20AND%%20tax_eq(9606)\n" "$ENA_BASE" "$s"
}

fetch_one() {
  local sample="$1"
  local outdir="$2"
  local sdir="$outdir/$sample"
  mkdir -p "$sdir"
  local manifest="$sdir/urls.txt"

  if [[ -s "$manifest" ]]; then
    echo "[$sample] using existing $manifest"
  else
    echo "[$sample] querying ENA..."
    curl -fsSL "$(ena_fastq_q "$sample")" | \
      awk -F'\t' 'NR>1 && $2!=""{gsub(/;/,"\n",$2); print "ftp://"$2}' > "$manifest" || true
  fi

  if [[ ! -s "$manifest" ]]; then
    echo "[$sample] no URLs found!" >&2
    return 0
  fi

  echo "[$sample] downloading with wget..."
  parallel -j8 --bar \
    'wget -c --no-verbose --show-progress --directory-prefix='"$sdir"' --no-hsts {}' \
    :::: "$manifest"

  echo "[$sample] done."
}

export -f fetch_one ena_fastq_q
export ENA_BASE

# Build sample list
if [[ "$IS_TSV" -eq 1 ]]; then
  mapfile -t samples < <(awk -F'\t' 'NR>1 && $1!=""{print $1}' "$INPUT" | sort -u)
else
  mapfile -t samples < <(awk 'NF && $0!~/^#/' "$INPUT" | sort -u)
fi

printf "%s\n" "${samples[@]}" | parallel -j"$PARALLEL" --eta fetch_one {} "$OUT"

echo "All downloads complete → $OUT/"
