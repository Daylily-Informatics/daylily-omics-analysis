#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  fqfetch.sh <samples.txt> <out_dir> [--nygc-fallback] [--only-manifest] [--parallel N]

Also supports a worker subcommand:
  fqfetch.sh one <sample> <out_dir> <nygc_fallback(0|1)> <only_manifest(0|1)>

Notes:
  - samples.txt: one SampleID per line (e.g., NA19360). If you have a TSV, do:
      awk -F'\t' 'NR>1{print $1}' smn_fetch_table.tsv | sort -u > samples.txt
  - Requires aria2c (preferred) or wget.
USAGE
}

ENA_BASE="https://www.ebi.ac.uk/ena/portal/api/search"

# Resolve absolute path to this script for worker calls
script_abs="$0"
case "$script_abs" in
  /*) ;;  # already absolute
  *) script_abs="$(cd "$(dirname "$script_abs")" && pwd)/$(basename "$script_abs")" ;;
esac

ena_fastq_q() {
  local s="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp,library_strategy,library_layout,instrument_model&query=sample_alias%%3D%%22%s%%22%%20AND%%20tax_eq(9606)\n" \
    "$ENA_BASE" "$s"
}
ena_nygc_q() {
  local s="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp,bam_ftp,submitted_ftp,cram_ftp,cram_index_ftp,instrument_model&query=sample_alias%%3D%%22%s%%22%%20AND%%20project_accession%%3D%%22PRJEB31736%%22%%20AND%%20tax_eq(9606)\n" \
    "$ENA_BASE" "$s"
}
phase3_dir() {
  printf "http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/%s/sequence_read/\n" "$1"
}

# ---------------------------
# Subcommand: process ONE sample
# ---------------------------
if [[ "${1:-}" == "one" ]]; then
  sample="$2"; out="$3"; nygc="${4:-0}"; only="${5:-0}"

  mkdir -p "$out/$sample"
  manf="$out/$sample/urls.txt"
  : > "$manf"

  # 1) ENA FASTQs (R1/R2 present as semicolon-separated fastq_ftp)
  curl -fsSL "$(ena_fastq_q "$sample")" 2>/dev/null \
    | awk -F'\t' 'NR>1 && $2!=""{gsub(/;/,"\n",$2); print $2}' \
    | sed 's#^#ftp://#' >> "$manf" || true

  # 2) Optional fallback: NYGC 30× PRJEB31736 CRAM/BAM/submitted_ftp
  if [[ "$nygc" == "1" ]] && ! grep -q '[[:graph:]]' "$manf"; then
    curl -fsSL "$(ena_nygc_q "$sample")" 2>/dev/null \
      | awk -F'\t' 'NR>1{for(i=1;i<=NF;i++){ if($i ~ /_ftp$/ && $i!=""){gsub(/;/,"\n",$i); print $i}}}' \
      | sed 's#^#ftp://#' >> "$manf" || true
  fi

  # 3) Last resort: list Phase3 dir for *_1/_2.filt.fastq.gz
  if ! grep -q '[[:graph:]]' "$manf"; then
    p3="$(phase3_dir "$sample")"
    curl -fsSL "$p3" 2>/dev/null \
      | grep -oE 'ERR[0-9]+_[12]\.filt\.fastq\.gz' | sort -u \
      | awk -v P="$p3" '{print P $1}' >> "$manf" || true
  fi

  # De-dupe
  awk 'NF && !seen[$0]++' "$manf" > "$manf.tmp" && mv "$manf.tmp" "$manf"

  # Only write manifest?
  if [[ "$only" == "1" ]]; then
    [[ -s "$manf" ]] || echo "WARN: $sample — no public URLs found" >&2
    exit 0
  fi

  # Downloader
  if command -v aria2c >/dev/null 2>&1; then
    ( cd "$out/$sample" && aria2c -c -x16 -s16 --auto-file-renaming=false --allow-overwrite=true -i "$manf" )
  elif command -v wget >/dev/null 2>&1; then
    ( cd "$out/$sample" && wget -c -i "$manf" )
  else
    echo "ERROR: need aria2c or wget" >&2
    exit 3
  fi
  exit 0
fi

# ---------------------------
# Main mode (batch)
# ---------------------------
if [[ "$#" -lt 2 ]]; then usage; exit 2; fi
INPUT="$1"; OUT="$2"; shift 2

NYGC_FALLBACK=0
ONLY_MANIFEST=0
PARALLEL=3

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --nygc-fallback) NYGC_FALLBACK=1 ;;
    --only-manifest) ONLY_MANIFEST=1 ;;
    --parallel) PARALLEL="${2:-3}"; shift ;;
    *) echo "WARN: unknown flag $1" >&2 ;;
  esac
  shift
done

mkdir -p "$OUT"

# Build sample list (plain text, one ID per line)
if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: cannot read $INPUT" >&2
  exit 2
fi

# Null-delimited for safe xargs
mapfile -d '' samples < <(awk 'NF && $0!~/^#/' "$INPUT" | tr -d '\r' | sed 's/$/\0/')

# Launch workers
printf '%s' "${samples[@]}" | xargs -0 -n1 -P "$PARALLEL" \
  bash -c 'script="$0"; sample="$1"; out="$2"; nygc="$3"; only="$4"; "$script" one "$sample" "$out" "$nygc" "$only"' \
  "$script_abs" _ "$OUT" "$NYGC_FALLBACK" "$ONLY_MANIFEST"
